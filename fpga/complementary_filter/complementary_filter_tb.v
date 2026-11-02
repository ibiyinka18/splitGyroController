`timescale 1ns/1ps
/* Checks the two behaviours the filter exists for.

1. it converges on the accelerometer angle when the gyro reads zero, so the
   absolute reference actually gets used
2. a constant gyro bias settles at a small bounded offset instead of
   integrating without limit, which is the whole reason for fusing at all

Also checks the fast path: a sudden gyro rate has to show up immediately
rather than being smoothed away, since that is what the gyro is for.
*/
module complementary_filter_tb;

    localparam CLK_PERIOD  = 83.333;
    localparam ALPHA_SHIFT = 10;

    reg clk = 1'b0;
    reg rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg               sample_valid;
    reg  signed [15:0] gyro_rate;
    reg  signed [15:0] accel_angle;
    wire signed [15:0] angle;
    wire               out_valid;

    complementary_filter #(.ALPHA_SHIFT(ALPHA_SHIFT)) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .gyro_rate    (gyro_rate),
        .accel_angle  (accel_angle),
        .angle        (angle),
        .out_valid    (out_valid)
    );

    integer errors = 0;

    initial begin
        $dumpfile("complementary_filter_tb.vcd");
        $dumpvars(0, complementary_filter_tb);
    end

    //drive n samples at the rate imu_controller would
    task run_samples(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                sample_valid = 1'b1;
                @(negedge clk);
                sample_valid = 1'b0;
                @(negedge clk);
                @(negedge clk);
            end
        end
    endtask

    task expect_near(input [255:0] name, input signed [15:0] got,
                     input signed [15:0] want, input integer tol);
        integer diff;
        begin
            diff = got - want;
            if (diff < 0) diff = -diff;
            if (diff > tol) begin
                $display("  FAIL  %0s: got %0d, expected %0d +/- %0d", name, got, want, tol);
                errors = errors + 1;
            end else begin
                $display("  pass  %0s: got %0d (expected %0d +/- %0d)", name, got, want, tol);
            end
        end
    endtask

    task expect_below(input [255:0] name, input signed [15:0] got, input integer limit);
        integer mag;
        begin
            mag = got;
            if (mag < 0) mag = -mag;
            if (mag > limit) begin
                $display("  FAIL  %0s: |%0d| exceeds %0d", name, got, limit);
                errors = errors + 1;
            end else begin
                $display("  pass  %0s: |%0d| within %0d", name, got, limit);
            end
        end
    endtask

    integer angle_at_4k;

    initial begin
        rst_n        = 1'b0;
        sample_valid = 1'b0;
        gyro_rate    = 16'sd0;
        accel_angle  = 16'sd0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        //--- tracks the accelerometer when the gyro says nothing ---
        //30 degrees = 5461 units. time constant is 1024 samples, so 8192
        //samples is about eight of them: converged to well under a percent
        $display("");
        $display("  --- accel tracking ---");
        gyro_rate   = 16'sd0;
        accel_angle = 16'sd5461;
        run_samples(8192);
        expect_near("converges on 30 deg", angle, 16'sd5461, 60);

        //--- a constant gyro bias must not integrate away ---
        //with accel pinned at zero the correction eventually cancels the bias.
        //unfused, 1 deg/s for 8192 samples at 800 Hz would be over 10 degrees
        $display("");
        $display("  --- bias rejection ---");
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        gyro_rate   = 16'sd16;       //~1 deg/s of uncorrected bias
        accel_angle = 16'sd0;
        run_samples(4096);
        angle_at_4k = angle;
        run_samples(4096);

        expect_below("bias stays bounded", angle, 400);
        if (angle > angle_at_4k + 40) begin
            $display("  FAIL  still climbing: %0d -> %0d over the second half",
                     angle_at_4k, angle);
            errors = errors + 1;
        end else begin
            $display("  pass  settled, not climbing: %0d -> %0d", angle_at_4k, angle);
        end

        //--- fast motion has to come straight through ---
        $display("");
        $display("  --- gyro responsiveness ---");
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        gyro_rate   = 16'sd3280;     //~200 deg/s, a brisk flick
        accel_angle = 16'sd0;        //accel disagrees, but slowly
        run_samples(400);            //half a second

        //200 deg/s for 0.5 s is ~100 deg = 18204 units, minus a little that
        //the accel has pulled back over that time
        expect_near("follows a 200 deg/s flick", angle, 16'sd17000, 2500);

        $display("");
        if (errors == 0) $display("  *** ALL CHECKS PASS ***");
        else             $display("  *** %0d CHECK(S) FAILED ***", errors);
        $display("");
        $finish;
    end

endmodule
