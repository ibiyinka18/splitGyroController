`timescale 1ns/1ps


module spi_master_tb;
// Inputs to DUT - the testbench drives these, so: reg
reg         clk;
reg         rst_n;
reg         start;
reg         hold_cs;
reg [7:0]   tx_byte;
reg         miso;


// Outputs from the DUT - the testbench only watches these;
wire [7:0]  rx_byte;
wire        busy;
wire        done;
wire        sclk;
wire        cs_n;
wire        mosi;

//12 Mhz system clock, matching the iCEstick
localparam CLK_PERIOD = 83.333; //ns
initial    clk = 1'b0;
always     #(CLK_PERIOD /2) clk = ~clk;

//instantiate the device under test
spi_master#(
    .CLK_DIV(6)
) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (start),
    .tx_byte    (tx_byte),
    .rx_byte    (rx_byte),
    .busy       (busy),
    .done       (done),
    .sclk       (sclk),
    .cs_n       (cs_n),
    .mosi       (mosi),
    .hold_cs    (hold_cs),
    .miso       (miso)
);
//Faake ICM-45686
localparam  [7:0] SLAVE_Reply = 8'h3C;

reg [7:0] captured  = 8'h00;  //wht master sends
reg [7:0] slave_reg = SLAVE_Reply;
integer   sclk_pulses   = 0;

always @(posedge sclk)  begin
    captured    <= {captured[6:0], mosi};
    sclk_pulses = sclk_pulses +1;
end

always@(negedge cs_n)
miso    <= slave_reg[7];

always  @(negedge sclk) if (!cs_n) begin
    slave_reg   <= slave_reg <<1;
    miso <= slave_reg[6];
end


//waveform dump for Vaporview
initial begin
    $dumpfile("spi_master_tb");
    $dumpvars(0, spi_master_tb);
end

//stimulus
initial begin
    rst_n   = 1'b0;     //start in reset
    start   = 1'b0;
    tx_byte = 8'h00;
    hold_cs = 1'b0;
    

    #200;
    rst_n   = 1'b1;     // release reset

    @(negedge clk);
    tx_byte = 8'h80;
    start   = 1'b1;
    @(negedge   clk);
    start   = 1'b0;


    wait (done);
    #500;
    $display("");
    $display(" SCLK pulses : %0d. (expect 8)", sclk_pulses);
    $display(" MOSI sent   : 0x%02h (expect 0x80)", captured);
    $display("rx_byte      : 0x%02h (expect 0x3C)", rx_byte);
    $display(" cs_n now    :  %b    (expect 1)",    cs_n);
    $display("");
    if(sclk_pulses== 8 && captured ==8'h80 &&
    rx_byte == 8'h3C && cs_n == 1'b1)
    $display(" *** ALL CHEckS PASS ***");
    else $display("** MISMATCH ***");
    $finish;
end



endmodule