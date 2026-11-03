`timescale 1ns/1ps
/* Top level for iCEstick bring-up of subsystems 1 and 3.

    ICM-45686 --SPI--> imu_controller --> sensor_packet --> uart_tx
                                                                |
                                                  FT2232H --> USB --> Mac

The uart goes to the onboard FTDI, so the same cable that programs the board
also carries the sensor stream back as a virtual serial port. No esp32 needed
to see real data.

What is NOT here: gyro_bias, cordic_atan2 and complementary_filter. Together
they need far more LUTs than the HX1K has left once the rest is placed, so
pitch and roll are tied low and the status bits read zero. All three are
verified in simulation and go in when the UP5K board arrives.

Raw sensor data is the right thing for bring-up anyway - the point of this
build is proving spi, the imu and the uart work on real silicon, and
unmodified readings are the clearest evidence of that. The packet format is
final either way, so the esp32 parser will not have to change.
*/
module top (
    input  wire clk_12mhz,

    //spi to the 6DOF IMU 27 Click
    output wire spi_sclk,
    output wire spi_cs_n,
    output wire spi_mosi,
    input  wire spi_miso,

    //to the onboard FT2232H, appears as a serial port on the host
    output wire uart_tx_pin,

    output reg  led_alive
);

    //the icestick has no reset button, so hold reset for the first 256 clocks
    //after configuration then release it
    reg [7:0] por_count = 8'd0;
    reg       rst_n     = 1'b0;

    always @(posedge clk_12mhz) begin
        if (por_count != 8'hFF) begin
            por_count <= por_count + 1'b1;
            rst_n     <= 1'b0;
        end else begin
            rst_n <= 1'b1;
        end
    end

    //imu_controller <> spi_master
    wire       spi_start;
    wire [7:0] spi_tx_byte;
    wire       spi_hold_cs;
    wire [7:0] spi_rx_byte;
    wire       spi_done;
    wire       spi_busy;

    //raw sample out of imu_controller, passed straight through on this board
    wire signed [15:0] accel_x, accel_y, accel_z;
    wire signed [15:0] gyro_x, gyro_y, gyro_z;
    wire               sample_valid;

    //sensor_packet <> uart_tx
    wire [7:0] uart_byte;
    wire       uart_start, uart_busy, uart_done, pkt_dropped, packet_sent;

    imu_controller ctrl (
        .clk         (clk_12mhz),
        .rst_n       (rst_n),
        .spi_start   (spi_start),
        .spi_tx_byte (spi_tx_byte),
        .spi_hold_cs (spi_hold_cs),
        .spi_rx_byte (spi_rx_byte),
        .spi_done    (spi_done),
        .accel_x     (accel_x),
        .accel_y     (accel_y),
        .accel_z     (accel_z),
        .gyro_x      (gyro_x),
        .gyro_y      (gyro_y),
        .gyro_z      (gyro_z),
        .data_valid  (sample_valid)
    );

    spi_master #(
        .CLK_DIV (6)                        //12 MHz / (2*6) = 1 MHz sclk
    ) spi (
        .clk     (clk_12mhz),
        .rst_n   (rst_n),
        .start   (spi_start),
        .hold_cs (spi_hold_cs),
        .tx_byte (spi_tx_byte),
        .rx_byte (spi_rx_byte),
        .busy    (spi_busy),
        .done    (spi_done),
        .sclk    (spi_sclk),
        .cs_n    (spi_cs_n),
        .mosi    (spi_mosi),
        .miso    (spi_miso)
    );


    sensor_packet #(
        .DECIMATE (4)                       //800 Hz in, 200 Hz of packets out
    ) packer (
        .clk          (clk_12mhz),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .accel_x      (accel_x),
        .accel_y      (accel_y),
        .accel_z      (accel_z),
        .gyro_x       (gyro_x),
        .gyro_y       (gyro_y),
        .gyro_z       (gyro_z),
        .pitch        (16'sd0),             //filter does not fit on HX1K
        .roll         (16'sd0),
        .calibrated   (1'b0),            //no bias module in this build
        .is_still     (1'b0),
        .tx_byte      (uart_byte),
        .tx_start     (uart_start),
        .tx_busy      (uart_busy),
        .tx_done      (uart_done),
        .dropped      (pkt_dropped),
        .packet_sent  (packet_sent)
    );

    uart_tx #(
        .CLKS_PER_BIT (104)                 //12 MHz / 115200
    ) serial (
        .clk       (clk_12mhz),
        .rst_n     (rst_n),
        .tx_start  (uart_start),
        .tx_byte   (uart_byte),
        .tx_serial (uart_tx_pin),
        .tx_busy   (uart_busy),
        .tx_done   (uart_done)
    );

    //packets go out at 200 Hz, far too fast to see, so divide down to ~1 Hz.
    //if this blinks, the whole chain from spi through to uart is running
    reg [7:0] packet_count = 8'd0;

    always @(posedge clk_12mhz) begin
        if (!rst_n) begin
            packet_count <= 8'd0;
            led_alive    <= 1'b0;
        end else if (packet_sent) begin
            if (packet_count == 8'd99) begin
                packet_count <= 8'd0;
                led_alive    <= ~led_alive;
            end else begin
                packet_count <= packet_count + 1'b1;
            end
        end
    end

endmodule
