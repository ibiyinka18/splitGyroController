`timescale 1ns/1ps
/* Checks gyro_bias against the offsets actually measured on hardware.

The bias figures used here came off the iCEstick capture of 2026-11-03,
averaged over 6074 stationary samples:

    gyro_x   +2.72 LSB  (+0.166 deg/s)
    gyro_y  -20.69 LSB  (-1.261 deg/s)   <- 4x the datasheet typical
    gyro_z   +3.54 LSB  (+0.216 deg/s)
    noise sd  ~1.3 LSB

What has to hold:
  1. with the controller still, the module learns those offsets and the
     corrected output falls to roughly zero
  2. real rotation passes through untouched, minus the learned offset
  3. movement part-way through a window throws that window away, so a moving
     sample can never be averaged into the bias estimate
  4. a later still window nudges the estimate rather than replacing it, since
     the underlying offset drifts on a thermal timescale and reacting fast
     would only track noise

STILL_SAMPLES is shortened to 64 here so the simulation stays quick; the
logic is identical at the 512 used in hardware.
*/
module gyro_bias_tb;

    localparam CLK_PERIOD   = 83.333;
    localparam STILL_SAMPLES = 64;
    localparam STILL_SHIFT   = 6;

    //measured on hardware
    localparam signed [15:0] BIAS_X = 16'sd3;
    localparam signed [15:0] BIAS_Y = -16'sd21;
    localparam signed [15:0] BIAS_Z = 16'sd4;

    reg clk = 1'b0;
    reg rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg               sample_valid;
    reg signed [15:0] gx_raw, gy_raw, gz_raw;

    wire signed [15:0] gx, gy, gz;
    wire               out_valid, is_still, calibrated;

    gyro_bias #(
        .STILL_SAMPLES (STILL_SAMPLES),
        .STILL_SHIFT   (STILL_SHIFT),
        .STILL_THRESH  (16'd164)        //~10 deg/s
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .gyro_x_raw   (gx_raw),
        .gyro_y_raw   (gy_raw),
        .gyro_z_raw   (gz_raw),
        .gyro_x       (gx),
        .gyro_y       (gy),
        .gyro_z       (gz),
        .out_valid    (out_valid),
        .is_still     (is_still),
        .calibrated   (calibrated)
    );

    integer errors = 0;

    initial begin
        $dumpfile("gyro_bias_tb.vcd");
        $dumpvars(0, gyro_bias_tb);
    end

    //one sample in, paced like imu_controller would
    task feed(input signed [15:0] x, input signed [15:0] y, input signed [15:0] z);
        begin
            @(negedge clk);
            gx_raw = x; gy_raw = y; gz_raw = z;
            sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
            @(negedge clk);
        end
    endtask

    //stationary: the measured offset plus a little noise, like the real part
    task feed_still(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                feed(BIAS_X + ($random % 2),
                     BIAS_Y + ($random % 2),
                     BIAS_Z + ($random % 2));
        end
    endtask

    task expect_near(input [255:0] name, input signed [15:0] got,
                     input signed [15:0] want, input integer tol);
        integer d;
        begin
            d = got - want;
            if (d < 0) d = -d;
            if (d > tol) begin
                $display("  FAIL  %0s: got %0d, expected %0d +/- %0d", name, got, want, tol);
                errors = errors + 1;
            end else begin
                $display("  pass  %0s: %0d (expected %0d +/- %0d)", name, got, want, tol);
            end
        end
    endtask

    initial begin
        rst_n        = 1'b0;
        sample_valid = 1'b0;
        gx_raw = 0; gy_raw = 0; gz_raw = 0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        //--- before any calibration, data must pass straight through ---
        $display("");
        $display("  --- passthrough before calibration ---");
        feed(16'sd100, -16'sd200, 16'sd300);
        expect_near("gyro_x uncorrected", gx,  16'sd100, 0);
        expect_near("gyro_y uncorrected", gy, -16'sd200, 0);
        if (calibrated !== 1'b0) begin
            $display("  FAIL  calibrated asserted before any still window");
            errors = errors + 1;
        end else $display("  pass  calibrated still low");

        //--- a full still window must learn the offset ---
        $display("");
        $display("  --- learning the measured offset ---");
        feed_still(STILL_SAMPLES + 2);

        if (calibrated !== 1'b1) begin
            $display("  FAIL  calibrated never asserted after a full still window");
            errors = errors + 1;
        end else $display("  pass  calibrated asserted");

        expect_near("learned bias_x", dut.bias_x, BIAS_X, 2);
        expect_near("learned bias_y", dut.bias_y, BIAS_Y, 2);
        expect_near("learned bias_z", dut.bias_z, BIAS_Z, 2);

        //--- and the corrected output should now sit near zero ---
        $display("");
        $display("  --- corrected output while still ---");
        feed(BIAS_X, BIAS_Y, BIAS_Z);
        expect_near("gyro_x corrected", gx, 16'sd0, 2);
        expect_near("gyro_y corrected", gy, 16'sd0, 2);
        expect_near("gyro_z corrected", gz, 16'sd0, 2);

        //--- real rotation passes through, offset removed ---
        //1000 LSB is about 61 deg/s
        $display("");
        $display("  --- real rotation ---");
        feed(16'sd1000 + BIAS_X, BIAS_Y, BIAS_Z);
        expect_near("gyro_x during rotation", gx, 16'sd1000, 2);
        expect_near("gyro_y unaffected",      gy, 16'sd0,    2);
        if (is_still !== 1'b0) begin
            $display("  FAIL  is_still asserted during rotation");
            errors = errors + 1;
        end else $display("  pass  is_still deasserted");

        //--- a moving sample must never land in the bias estimate ---
        //half a window of still, then one big movement, then still again.
        //if the window were not discarded the estimate would be dragged up
        $display("");
        $display("  --- movement discards the window ---");
        feed_still(STILL_SAMPLES / 2);
        feed(16'sd5000, 16'sd5000, 16'sd5000);      //a sharp flick
        feed_still(STILL_SAMPLES / 2);

        expect_near("bias_x unpolluted", dut.bias_x, BIAS_X, 2);
        expect_near("bias_y unpolluted", dut.bias_y, BIAS_Y, 2);

        //--- a later window nudges rather than replaces ---
        //pretend the part warmed and the offset moved by 40 LSB. one window
        //should close about a quarter of that gap, not all of it
        $display("");
        $display("  --- slow blend on re-calibration ---");
        //clear the half-filled window left by the test above, otherwise the
        //closing window averages old and new offsets together and the blend
        //looks smaller than it is
        feed(16'sd5000, 16'sd5000, 16'sd5000);
        begin : warm
            integer i;
            for (i = 0; i < STILL_SAMPLES + 2; i = i + 1)
                feed(BIAS_X + 16'sd40, BIAS_Y, BIAS_Z);
        end
        expect_near("bias_x moved ~1/4 of the way", dut.bias_x, BIAS_X + 16'sd10, 3);

        $display("");
        if (errors == 0) $display("  *** ALL CHECKS PASS ***");
        else             $display("  *** %0d CHECK(S) FAILED ***", errors);
        $display("");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("  *** TIMEOUT ***");
        $finish;
    end

endmodule