/* atan2(y, x) using CORDIC, in vectoring mode.

Rotates the input vector toward the x-axis in fixed steps and keeps a running
total of how far it rotated. When y reaches zero the accumulated total is the
original angle. The step sizes are chosen as atan(2^-i), which makes every
rotation collapse into a shift and an add, so no multiplier is needed.

One iteration per clock. At 800 Hz sampling there are ~15000 clocks per sample
and this needs 14, so the serial version costs almost nothing in time and a
fraction of the area a pipelined one would.

Angle units: the full 16-bit signed range spans +/-180 degrees, so one LSB is
about 0.0055 degrees. Conversion to degrees happens downstream in firmware.
*/
module cordic_atan2 #(
    //past 14 the table entry rounds below one LSB, so extra steps do nothing
    parameter ITERATIONS = 14
) (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               start,
    input  wire signed [15:0] x_in,
    input  wire signed [15:0] y_in,

    output reg  signed [15:0] angle,
    output reg                done,
    output reg                busy
);

    localparam signed [15:0] ANGLE_90 = 16'sd16384;   //quarter of the 16-bit span

    //atan(2^-i) scaled so 180 degrees = 32768
    function signed [15:0] atan_step(input integer i);
        case (i)
            0:  atan_step = 16'sd8192;
            1:  atan_step = 16'sd4836;
            2:  atan_step = 16'sd2555;
            3:  atan_step = 16'sd1297;
            4:  atan_step = 16'sd651;
            5:  atan_step = 16'sd326;
            6:  atan_step = 16'sd163;
            7:  atan_step = 16'sd81;
            8:  atan_step = 16'sd41;
            9:  atan_step = 16'sd20;
            10: atan_step = 16'sd10;
            11: atan_step = 16'sd5;
            12: atan_step = 16'sd3;
            13: atan_step = 16'sd1;
            14: atan_step = 16'sd1;
            default: atan_step = 16'sd0;
        endcase
    endfunction

    //two extra bits of headroom. cordic inflates the vector by ~1.647 over the
    //full run, which we don't care about for angle but mustn't be allowed to
    //overflow mid-rotation
    reg signed [17:0] x, y;
    reg signed [15:0] z;
    reg [4:0] iter;

    localparam IDLE   = 2'd0;
    localparam ROTATE = 2'd1;
    localparam FINISH = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            x     <= 18'sd0;
            y     <= 18'sd0;
            z     <= 16'sd0;
            iter  <= 5'd0;
            angle <= 16'sd0;
            done  <= 1'b0;
            busy  <= 1'b0;
        end else begin
            done <= 1'b0;                   //one-clk pulse, set in FINISH

            case (state)

            IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    //the rotation only converges for x > 0, so swing the left
                    //half-plane into the right one first and seed z with the
                    //90 degrees we just took out
                    if (x_in >= 0) begin
                        x <= {{2{x_in[15]}}, x_in};
                        y <= {{2{y_in[15]}}, y_in};
                        z <= 16'sd0;
                    end else if (y_in >= 0) begin
                        x <= {{2{y_in[15]}}, y_in};
                        y <= -{{2{x_in[15]}}, x_in};
                        z <= ANGLE_90;
                    end else begin
                        x <= -{{2{y_in[15]}}, y_in};
                        y <= {{2{x_in[15]}}, x_in};
                        z <= -ANGLE_90;
                    end
                    iter  <= 5'd0;
                    busy  <= 1'b1;
                    state <= ROTATE;
                end
            end

            ROTATE: begin
                if (iter == ITERATIONS) begin
                    state <= FINISH;
                end else begin
                    //drive y toward zero. the sign of y says which way to turn
                    if (y > 0) begin
                        x <= x + (y >>> iter);
                        y <= y - (x >>> iter);
                        z <= z + atan_step(iter);
                    end else begin
                        x <= x - (y >>> iter);
                        y <= y + (x >>> iter);
                        z <= z - atan_step(iter);
                    end
                    iter <= iter + 1'b1;
                end
            end

            FINISH: begin
                angle <= z;
                done  <= 1'b1;
                busy  <= 1'b0;
                state <= IDLE;
            end

            endcase
        end
    end

endmodule
