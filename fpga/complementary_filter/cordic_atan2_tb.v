`timescale 1ns/1ps
/* Checks cordic_atan2 against known atan2 values across all four quadrants.

Vectors were generated from real atan2 and scaled so 180 degrees = 32768.
Each one is a point at radius 8000 and a known angle, so a quadrant or
pre-rotation mistake shows up immediately rather than looking plausible.
*/
module cordic_atan2_tb;

    localparam CLK_PERIOD = 83.333;

    //one LSB is ~0.0055 deg, so this is about a quarter of a degree
    localparam TOL = 50;

    reg clk = 1'b0;
    reg rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg               start;
    reg  signed [15:0] x_in, y_in;
    wire signed [15:0] angle;
    wire               done, busy;

    cordic_atan2 #(.ITERATIONS(14)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .start (start),
        .x_in  (x_in),
        .y_in  (y_in),
        .angle (angle),
        .done  (done),
        .busy  (busy)
    );

    integer errors = 0;
    integer checks = 0;

    initial begin
        $dumpfile("cordic_atan2_tb.vcd");
        $dumpvars(0, cordic_atan2_tb);
    end

    //feed one vector, wait for the result, compare against atan2
    task check(input signed [15:0] x, input signed [15:0] y,
               input signed [15:0] expect);
        integer diff;
        begin
            @(negedge clk);
            x_in  = x;
            y_in  = y;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            wait (done);
            @(negedge clk);

            checks = checks + 1;
            diff = angle - expect;
            if (diff < 0) diff = -diff;

            if (diff > TOL) begin
                $display("  FAIL  x=%6d y=%6d  got %6d  expected %6d  (off by %0d)",
                         x, y, angle, expect, diff);
                errors = errors + 1;
            end else begin
                $display("  pass  x=%6d y=%6d  got %6d  expected %6d",
                         x, y, angle, expect);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        x_in  = 16'sd0;
        y_in  = 16'sd0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        $display("");
        check(   8000,       0,       0);   //     0 deg
        check(   7727,    2071,    2731);   //    15 deg
        check(   6928,    4000,    5461);   //    30 deg
        check(   5657,    5657,    8192);   //    45 deg
        check(   4000,    6928,   10923);   //    60 deg
        check(      0,    8000,   16384);   //    90 deg
        check(  -4000,    6928,   21845);   //   120 deg
        check(  -5657,    5657,   24576);   //   135 deg
        check(  -7878,    1389,   30948);   //   170 deg
        check(  -7999,     140,   32586);   //   179 deg
        check(   7727,   -2071,   -2731);   //   -15 deg
        check(   6928,   -4000,   -5461);   //   -30 deg
        check(   5657,   -5657,   -8192);   //   -45 deg
        check(      0,   -8000,  -16384);   //   -90 deg
        check(  -5657,   -5657,  -24576);   //  -135 deg
        check(  -7999,    -140,  -32586);   //  -179 deg

        $display("");
        if (errors == 0) $display("  *** ALL %0d CHECKS PASS ***", checks);
        else             $display("  *** %0d of %0d CHECKS FAILED ***", errors, checks);
        $display("");
        $finish;
    end

    //never let a stuck handshake hang the run
    initial begin
        #2_000_000;
        $display("  *** TIMEOUT  state=%0d iter=%0d ***", dut.state, dut.iter);
        $finish;
    end

endmodule