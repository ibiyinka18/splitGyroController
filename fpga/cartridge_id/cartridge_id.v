/* Reads one cartridge receptacle's hardware-ID pins and reports a stable id.

Handles a single receptacle. The left half has two and the right half one, so
top.v instantiates this once or twice as the board needs rather than the
module carrying a count it cannot know. Same idea as spi_master driving both
the IMU and the ADC.

The fpga side is pulled high and the cartridge grounds a pattern, so all-ones
means nothing is plugged in:

    11  none
    10  thumbstick
    01  d-pad
    00  spare

Two problems to solve, both the same shape as reading a button:

  the pins are asynchronous - a cartridge gets inserted whenever the user
  feels like it, with no relation to our clock. a signal changing right at a
  clock edge can leave a flip-flop metastable and propagate a value that is
  neither 0 nor 1, so every pin goes through two flip-flops before anything
  looks at it.

  the contacts bounce - worse than a button, because insertion is slow and
  the user may wiggle the connector. so a new value only becomes official
  after it has held steady for DEBOUNCE_CYCLES.

cart_changed pulses when the stable id moves, so the esp32 can reload its
input mapping on an event rather than polling.
*/
module cartridge_id #(
    //~50 ms at 12 MHz. insertion bounce runs much longer than the ~1-5 ms of
    //a button, and nothing here is latency sensitive, so err long
    parameter [23:0] DEBOUNCE_CYCLES = 24'd600_000
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [1:0] id_pins,       //raw, asynchronous, pulled high

    output reg  [1:0] cart_id,       //debounced
    output reg        cart_changed   //one-clk pulse when cart_id moves
);

    localparam [1:0] ID_NONE = 2'b11;   //nothing grounding either line

    //two flip-flops against metastability. sync1 may settle to a bogus value
    //on any given edge; sync2 is what the rest of the design is allowed to see
    reg [1:0] sync1, sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= ID_NONE;
            sync2 <= ID_NONE;
        end else begin
            sync1 <= id_pins;
            sync2 <= sync1;
        end
    end

    //candidate value and how long it has held
    reg [1:0]  candidate;
    reg [23:0] stable_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            candidate    <= ID_NONE;
            stable_count <= 24'd0;
            cart_id      <= ID_NONE;
            cart_changed <= 1'b0;
        end else begin
            cart_changed <= 1'b0;

            if (sync2 != candidate) begin
                //still moving, so restart the timer on the new value
                candidate    <= sync2;
                stable_count <= 24'd0;
            end else if (stable_count != DEBOUNCE_CYCLES) begin
                stable_count <= stable_count + 1'b1;
            end else if (cart_id != candidate) begin
                //held long enough and it is genuinely different
                cart_id      <= candidate;
                cart_changed <= 1'b1;
            end
        end
    end

endmodule