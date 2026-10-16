module spi_master #(
    parameter CLK_DIV =6
)(
    input   wire          clk,
    input   wire          rst_n,
    input   wire          start,
    input   wire          hold_cs,
    input   wire [7:0]    tx_byte,
    output  reg  [7:0]    rx_byte,
    output  reg           busy,
    output  reg           done,

    output  reg           sclk,
    output  reg           cs_n,
    output  reg           mosi,
    input   wire          miso
);



reg [2:0]  div_counter;
reg        tick;

always @(posedge clk or negedge rst_n) begin
if(!rst_n) begin
div_counter <= 3'd0;
tick        <= 1'b0;
end else if(div_counter == CLK_DIV -1) begin
div_counter <= 3'd0;
tick        <= 1'b1;   //fire for excactly one clk cycle
end else begin
div_counter <= div_counter + 1'b1;
tick        <= 1'b0;
end
end

//State machine
localparam IDLE     = 2'd0;
localparam TRANSFER = 2'd1;
localparam FINISH  = 2'd2;

reg [1:0] state;

reg [7:0] shift_reg; // holds the byte being shifted in/out
reg [3:0] bit_count;//counts 0,,,7

always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state       <=IDLE;
        cs_n        <=1'b1;
        sclk        <=1'b0;
        mosi        <=1'b0;
        busy        <=1'b0;
        done        <=1'b0;
        rx_byte     <=8'd0;
        shift_reg   <=8'd0;
        bit_count   <=4'd0;
    end else begin
        done <= 1'b0;                   //default low: overdden in FINNISH
        case (state)
        IDLE: begin
            cs_n <= hold_cs ? 1'b0 : 1'b1;
            sclk <= 1'b0;
            busy <= 1'b0;
            if (start) begin
                shift_reg <= tx_byte;
                mosi      <= tx_byte[7]; //present MSB before first edge
                bit_count <= 4'd0;
                cs_n      <= 1'b0;
                busy      <= 1'b1;
                state     <= TRANSFER;
            end
        end
        TRANSFER: begin
            if(tick)begin
            sclk <=~sclk;

            if(!sclk)begin
                //sclk is low so this tick makes it RISE-> sample
                shift_reg <= {shift_reg[6:0],miso};
                bit_count <= bit_count + 1'b1;
            end else begin
                //SCLk is high, os this tick makes it fall -> drive
                if (bit_count == 4'd8)
                state <= FINISH;
                else mosi <= shift_reg[7];
            end
            end
        end
        FINISH: begin
            cs_n <= hold_cs ? 1'b0 : 1'b1;
            rx_byte <= shift_reg;
            done    <= 1'b1;
            busy    <= 1'b0;
            state   <= IDLE;
        end

        endcase
    end
end
endmodule

        