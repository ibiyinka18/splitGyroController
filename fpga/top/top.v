`timescale 1ns/1ps
/*Top level for iCEstick bring-up for subsystem 1.
wires imu_controller + spi_master to the physical PMOD pins and blinks an LED so you can see sample aquisition without a probe.
*/
module top (
    input wire clk_12mhz,
    output wire spi_sclk,
    output wire spi_cs_n,
    output wire spi_mosi,
    input wire  spi_miso,
    output reg  led_alive

);

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


//imu7 controller <> spi_masteer
wire            spi_start;
wire [7:0]      spi_tx_byte;
wire            spi_hold_cs;
wire [7:0]      spi_rx_byte;
wire            spi_done;
wire            spi_busy;

wire signed [15:0] accel_x, accel_y, accel_z;
wire signed [15:0] gyro_x, gyro_y, gyro_z;
wire               data_valid;

imu_controller  ctrl(
    .clk        (clk_12mhz),
    .rst_n      (rst_n),
    .spi_start  (spi_start),
    .spi_tx_byte    (spi_tx_byte),
    .spi_hold_cs    (spi_hold_cs),
    .spi_rx_byte    (spi_rx_byte),
    .spi_done       (spi_done),
    .accel_x         (accel_x),
    .accel_y         (accel_y),
    .accel_z         (accel_z),
    .gyro_x          (gyro_x),
    .gyro_y          (gyro_y),
    .gyro_z          (gyro_z),
    .data_valid      (data_valid)
);

spi_master #(
    .CLK_DIV (6)        //12Mhz (2*6) = 1mhz SCLk
) spi(
    .clk        (clk_12mhz),
    .rst_n      (rst_n),
    .start      (spi_start),
    .hold_cs    (spi_hold_cs),
    .tx_byte    (spi_tx_byte),
    .rx_byte    (spi_rx_byte),
    .busy       (spi_busy),
    .done       (spi_done),
    .sclk       (spi_sclk),
    .cs_n       (spi_cs_n),
    .mosi       (spi_mosi),
    .miso       (spi_miso)
);

// heartbeat data valiudn fires 9.6khz too fast to see so gets divided down to roughly 1HZ.
reg[12:0] sample_count = 13'd0;

always@(posedge clk_12mhz) begin
    if(!rst_n) begin
        sample_count <= 13'd0;
        led_alive    <= 1'b0;
    end else if (data_valid) begin
        sample_count <= sample_count + 1'b1;
        if(sample_count == 13'h1FFF)
        led_alive <= ~led_alive;
    end
end
endmodule