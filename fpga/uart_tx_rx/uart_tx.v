/* UART transmitter, 8 data bits, no parity, 1 stop bit.

Unlike SPI there is no clock wire, so both ends have to independently agree on
the bit rate. Everything here hangs off that: a counter times out one bit
period and the state machine walks start -> 8 data -> stop.

The line idles high. A falling edge is what tells the receiver a byte is
starting, which is why the start bit is low and the stop bit is high - the
stop bit guarantees the line is back up so the next start bit is a real edge.

Bit order is LSB first, the opposite of SPI.
*/
module uart_tx #(
    //12 MHz / 1 Mbaud = 12 exactly, so there is no baud error at all. 115200
    //would be 104.17 -> 104, which works, but a 21-byte packet takes 1.82 ms
    //at that rate and would rival the radio hop in the latency budget. at
    //1 Mbaud the same packet is 0.21 ms
    parameter CLKS_PER_BIT = 12
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_start,      //pulse one clk to send tx_byte
    input  wire [7:0] tx_byte,

    output reg        tx_serial,
    output reg        tx_busy,
    output reg        tx_done        //one-clk pulse when the stop bit ends
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;            //times out one bit period
    reg [2:0]  bit_index;            //position within the byte
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx_serial <= 1'b1;       //idle high
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            tx_done <= 1'b0;

            case (state)

            IDLE: begin
                tx_serial <= 1'b1;
                tx_busy   <= 1'b0;
                clk_count <= 16'd0;
                bit_index <= 3'd0;

                if (tx_start) begin
                    shift_reg <= tx_byte;
                    tx_serial <= 1'b0;          //start bit goes out immediately
                    tx_busy   <= 1'b1;
                    state     <= START;
                end
            end

            START: begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 16'd0;
                    tx_serial <= shift_reg[0];  //lsb first
                    state     <= DATA;
                end else begin
                    clk_count <= clk_count + 1'b1;
                end
            end

            DATA: begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 16'd0;
                    if (bit_index == 3'd7) begin
                        tx_serial <= 1'b1;      //stop bit
                        state     <= STOP;
                    end else begin
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        tx_serial <= shift_reg[1];
                        bit_index <= bit_index + 1'b1;
                    end
                end else begin
                    clk_count <= clk_count + 1'b1;
                end
            end

            STOP: begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 16'd0;
                    tx_done   <= 1'b1;
                    tx_busy   <= 1'b0;
                    state     <= IDLE;
                end else begin
                    clk_count <= clk_count + 1'b1;
                end
            end

            endcase
        end
    end

endmodule
