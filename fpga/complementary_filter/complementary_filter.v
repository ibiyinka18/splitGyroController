/* Fuses one gyro axis with its accelerometer-derived angle.

The gyro is accurate over short intervals but its small zero-rate offset
integrates into growing error. The accelerometer never drifts, since gravity
does not move, but it reads every hand movement as if it were tilt. Each
sensor covers the other's weakness, hence "complementary".

    pred  = angle + gyro * dt
    angle = pred + (1-alpha) * (accel_angle - pred)

which is the usual alpha*(...) + (1-alpha)*(...) rearranged to need one
multiply instead of two. Choosing (1-alpha) as a power of two turns that
multiply into a shift, which costs no logic at all.

Handles one axis, so instantiate twice for pitch and roll. Yaw is deliberately
not fused: gravity gives no yaw reference, so there is nothing to correct
against and the accel term would only inject noise.
*/
module complementary_filter #(
    //time constant is dt * 2^ALPHA_SHIFT. at 800 Hz, 10 gives ~1.3 s: the gyro
    //owns anything fast, the accel only pulls back slow drift. dropping this
    //lets accel noise through, raising it lets more drift accumulate
    parameter ALPHA_SHIFT = 10,

    //gyro LSB -> angle units, in Q8. one LSB at +/-2000dps is 1/16.4 deg/s,
    //over 1/800 s, scaled so 180 deg = 32768, times 256 for the fraction:
    //  256 / (16.4 * 800) * (32768/180) = 909.4
    //written as a constant multiply so synthesis folds it into shifts and adds
    parameter signed [15:0] GYRO_SCALE = 16'sd910
) (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               sample_valid,
    input  wire signed [15:0] gyro_rate,      //bias corrected, raw LSB
    input  wire signed [15:0] accel_angle,    //from cordic_atan2

    output reg  signed [15:0] angle,          //fused, same units as accel_angle
    output reg                out_valid
);

    //Q16.8 accumulator. the per-sample gyro contribution is well under one
    //whole angle unit, so without fractional bits it would round away entirely
    reg signed [23:0] angle_q8;

    //accel reading promoted to the same fixed-point scale
    wire signed [23:0] accel_q8 = {{8{accel_angle[15]}}, accel_angle} <<< 8;

    //how far the gyro says we turned since the last sample
    wire signed [31:0] gyro_step_wide = gyro_rate * GYRO_SCALE;
    wire signed [23:0] gyro_step      = gyro_step_wide[31:8];

    //dead reckoning from the gyro alone
    wire signed [23:0] pred = angle_q8 + gyro_step;

    //and the correction back toward gravity
    wire signed [23:0] error = accel_q8 - pred;

    //the fused result. named so both the accumulator and the output can take
    //it, since verilog won't let you part-select an expression inline
    wire signed [23:0] angle_next = pred + (error >>> ALPHA_SHIFT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            angle_q8  <= 24'sd0;
            angle     <= 16'sd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= 1'b0;

            if (sample_valid) begin
                angle_q8  <= angle_next;
                angle     <= angle_next[23:8];   //drop the fraction for the output
                out_valid <= 1'b1;
            end
        end
    end

endmodule