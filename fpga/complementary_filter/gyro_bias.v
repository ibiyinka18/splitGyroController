/* Removes the gyroscope zero-rate offset.

Every MEMS gyro reads slightly non-zero when stationary, from manufacturing
asymmetry and package stress. That offset integrates into steadily growing
angle error, so it has to come out before any filtering.
Offset moves with temperature due to chips self heating

This module watches for the controller being steady/stationary and re learns the offset each time
tracking drift caused by thermal issues without the user doing anything.
*/
module gyro_bias #(
    parameter           STILL_SAMPLES = 512,               // ~0.64 s at 800mhz
    parameter           STILL_SHIFT   =9,                 //lof2 (still samples)
    parameter   [15:0]  STILL_THRESH  = 16'd164          // ~10 deg at 16.4 lsb/(deg/s)
)(
    input wire              clk,
    input wire              rst_n,

    // raw samples form imu_controller
    input wire              sample_valid,
    input wire signed  [15:0] gyro_x_raw,
    input wire signed  [15:0] gyro_y_raw,
    input wire signed  [15:0] gyro_z_raw,

    //bias corrected input
    output reg signed [15:0] gyro_x,
    output reg signed [15:0] gyro_y,
    output reg signed [15:0] gyro_z,
    output reg               out_valid,


    //status
    output reg               is_still,  //debating stillness
    output reg               calibrated //bias done at least once

);

    //current offset estimate, subtracted from every sample
    reg signed [15:0] bias_x, bias_y, bias_z;

    //running sum over a still period. 16-bit samples summed STILL_SAMPLES
    //times needs 16 + STILL_SHIFT bits, plus a sign bit
    reg signed [25:0] acc_x, acc_y, acc_z;

    //width tracks the parameter, so raising STILL_SAMPLES can't silently wrap
    reg [$clog2(STILL_SAMPLES):0] still_count;

    //|sample| for the stillness test. ~x + 1 is two's complement negate,
    //so this reads "if the sign bit is set, negate it"
    reg [15:0] abs_x, abs_y, abs_z;

    always @(gyro_x_raw or gyro_y_raw or gyro_z_raw) begin
        abs_x = gyro_x_raw[15] ? (~gyro_x_raw + 1'b1) : gyro_x_raw;
        abs_y = gyro_y_raw[15] ? (~gyro_y_raw + 1'b1) : gyro_y_raw;
        abs_z = gyro_z_raw[15] ? (~gyro_z_raw + 1'b1) : gyro_z_raw;
    end

    //no axis rotating faster than the threshold = not being moved
    wire sample_is_still = (abs_x < STILL_THRESH) &&
                           (abs_y < STILL_THRESH) &&
                           (abs_z < STILL_THRESH);

    //average of the still period. the accumulator holds STILL_SAMPLES-1 samples
    //when the window closes, so fold in the current one here to average over a
    //full 512 rather than 511. arithmetic shift, so negative sums stay negative
    wire signed [25:0] avg_x_full = (acc_x + gyro_x_raw) >>> STILL_SHIFT;
    wire signed [25:0] avg_y_full = (acc_y + gyro_y_raw) >>> STILL_SHIFT;
    wire signed [25:0] avg_z_full = (acc_z + gyro_z_raw) >>> STILL_SHIFT;

    wire signed [15:0] avg_x = avg_x_full[15:0];
    wire signed [15:0] avg_y = avg_y_full[15:0];
    wire signed [15:0] avg_z = avg_z_full[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_x      <= 16'sd0;
            bias_y      <= 16'sd0;
            bias_z      <= 16'sd0;
            acc_x       <= 26'sd0;
            acc_y       <= 26'sd0;
            acc_z       <= 26'sd0;
            still_count <= 10'd0;
            gyro_x      <= 16'sd0;
            gyro_y      <= 16'sd0;
            gyro_z      <= 16'sd0;
            out_valid   <= 1'b0;
            is_still    <= 1'b0;
            calibrated  <= 1'b0;
        end else begin
            out_valid <= 1'b0;              //default low, pulses with each sample

            if (sample_valid) begin
                //correct and hand on straight away. calibration runs alongside
                //and never holds up the data path
                gyro_x    <= gyro_x_raw - bias_x;
                gyro_y    <= gyro_y_raw - bias_y;
                gyro_z    <= gyro_z_raw - bias_z;
                out_valid <= 1'b1;

                is_still <= sample_is_still;

                if (sample_is_still) begin
                    if (still_count == STILL_SAMPLES - 1) begin
                        //a full quiet window, so update the estimate
                        if (!calibrated) begin
                            //nothing worth keeping yet, take it outright
                            bias_x <= avg_x;
                            bias_y <= avg_y;
                            bias_z <= avg_z;
                            calibrated <= 1'b1;
                        end else begin
                            //move a quarter of the way. the real offset drifts
                            //on a thermal timescale, so reacting fast would
                            //only be chasing noise
                            bias_x <= bias_x + ((avg_x - bias_x) >>> 2);
                            bias_y <= bias_y + ((avg_y - bias_y) >>> 2);
                            bias_z <= bias_z + ((avg_z - bias_z) >>> 2);
                        end

                        acc_x       <= 26'sd0;
                        acc_y       <= 26'sd0;
                        acc_z       <= 26'sd0;
                        still_count <= 10'd0;
                    end else begin
                        acc_x       <= acc_x + gyro_x_raw;
                        acc_y       <= acc_y + gyro_y_raw;
                        acc_z       <= acc_z + gyro_z_raw;
                        still_count <= still_count + 1'b1;
                    end
                end else begin
                    //movement, so this window is spoiled. start over
                    acc_x       <= 26'sd0;
                    acc_y       <= 26'sd0;
                    acc_z       <= 26'sd0;
                    still_count <= 10'd0;
                end
            end
        end
    end

endmodule