/* Serialises one sensor sample into a framed packet and feeds it to uart_tx.

    0xAA 0x55 | seq | status | 12 raw bytes | 4 angle bytes | xor checksum
       2      +  1  +   1    +     12       +      4        +     1   = 21 bytes

The two sync bytes exist because a uart stream has no inherent packet
boundary. Drop one byte and the receiver reads the tail of one sample and the
head of the next forever, producing data that looks plausible but is wrong.
Two bytes rather than one because 0xAA alone shows up inside real sensor data
often enough to false-lock on.

seq increments every packet, so the receiver can spot drops rather than
silently accepting a gap. The checksum is an xor of everything between the
sync and itself, which costs nothing in hardware and catches single-byte
corruption.

All multi-byte fields are big-endian, high byte first, matching the order the
ICM-45686 returns them in.

Sending is decimated: the filter runs at the full 800 Hz sample rate because
oversampling helps the maths, but only every DECIMATE-th result is
transmitted. At 200 Hz this is ~42 kbps, comfortable inside 115200, and BLE
HID reports at around 250 Hz anyway so a faster link would gain nothing
end to end.
*/
module sensor_packet #(
    parameter DECIMATE = 4                 //800 Hz in, 200 Hz out
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sample_valid,
    input  wire signed [15:0] accel_x,
    input  wire signed [15:0] accel_y,
    input  wire signed [15:0] accel_z,
    input  wire signed [15:0] gyro_x,
    input  wire signed [15:0] gyro_y,
    input  wire signed [15:0] gyro_z,
    input  wire signed [15:0] pitch,       //zero until the filter is fitted
    input  wire signed [15:0] roll,
    input  wire        calibrated,
    input  wire        is_still,
    input  wire [1:0]  cart_a,             //receptacle A id, 11 = nothing inserted
    input  wire [1:0]  cart_b,             //receptacle B, tied to 11 on the right half

    //to uart_tx
    output reg  [7:0]  tx_byte,
    output reg         tx_start,
    input  wire        tx_busy,
    input  wire        tx_done,

    output reg         dropped,            //pulses if a sample arrives mid-packet
    output reg         packet_sent         //one-clk pulse when a whole packet is out
);

    //status byte layout, so firmware and rtl cannot drift apart:
    //  [0] calibrated  [1] is_still  [3:2] cart_a  [5:4] cart_b  [7:6] spare
    //
    //a receptacle id of 11 means nothing is inserted, so presence needs no
    //separate flag. the right half has only one receptacle and ties cart_b to
    //11, which keeps one packet format across both halves
    wire [7:0] status = {2'b00, cart_b, cart_a, is_still, calibrated};

    localparam SYNC0       = 8'hAA;
    localparam SYNC1       = 8'h55;
    localparam PACKET_LEN  = 21;

    //snapshot taken when a sample is accepted, so the packet is internally
    //consistent even though new samples keep arriving while it goes out
    reg [7:0] pkt [0:PACKET_LEN-1];

    reg [4:0] byte_index;
    reg [7:0] seq;
    reg       sending;

    //set when the next byte is ready to be handed to uart_tx. kept separate
    //from the done signal because uart_tx drops tx_busy and raises tx_done on
    //the same edge, so an if/else on those two would always take the first arm
    reg       byte_pending;

    reg [$clog2(DECIMATE):0] decim_count;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_index  <= 5'd0;
            seq         <= 8'd0;
            sending     <= 1'b0;
            tx_start    <= 1'b0;
            tx_byte     <= 8'd0;
            decim_count <= 0;
            dropped      <= 1'b0;
            packet_sent  <= 1'b0;
            byte_pending <= 1'b0;
            for (i = 0; i < PACKET_LEN; i = i + 1) pkt[i] <= 8'd0;
        end else begin
            tx_start    <= 1'b0;
            dropped     <= 1'b0;
            packet_sent <= 1'b0;

            //count every sample, not just the ones arriving while idle. a
            //packet takes longer than one sample period, so samples do land
            //mid-transmission and skipping them here would make the output
            //rate both wrong and irregular
            if (sample_valid) begin
                if (decim_count == DECIMATE - 1) begin
                    decim_count <= 0;

                  if (sending) begin
                    //the previous packet is still going out, so this one is
                    //genuinely lost. there is plenty of slack at 200 Hz over
                    //115200, so this firing means the rate or baud needs a look
                    dropped <= 1'b1;
                  end else begin
                    pkt[0]  <= SYNC0;
                    pkt[1]  <= SYNC1;
                    pkt[2]  <= seq;
                    pkt[3]  <= status;

                    pkt[4]  <= accel_x[15:8];   pkt[5]  <= accel_x[7:0];
                    pkt[6]  <= accel_y[15:8];   pkt[7]  <= accel_y[7:0];
                    pkt[8]  <= accel_z[15:8];   pkt[9]  <= accel_z[7:0];
                    pkt[10] <= gyro_x[15:8];    pkt[11] <= gyro_x[7:0];
                    pkt[12] <= gyro_y[15:8];    pkt[13] <= gyro_y[7:0];
                    pkt[14] <= gyro_z[15:8];    pkt[15] <= gyro_z[7:0];
                    pkt[16] <= pitch[15:8];     pkt[17] <= pitch[7:0];
                    pkt[18] <= roll[15:8];      pkt[19] <= roll[7:0];

                    //xor of bytes 2..19, i.e. everything after the sync and
                    //before the checksum itself
                    pkt[20] <= seq
                             ^ status
                             ^ accel_x[15:8] ^ accel_x[7:0]
                             ^ accel_y[15:8] ^ accel_y[7:0]
                             ^ accel_z[15:8] ^ accel_z[7:0]
                             ^ gyro_x[15:8]  ^ gyro_x[7:0]
                             ^ gyro_y[15:8]  ^ gyro_y[7:0]
                             ^ gyro_z[15:8]  ^ gyro_z[7:0]
                             ^ pitch[15:8]   ^ pitch[7:0]
                             ^ roll[15:8]    ^ roll[7:0];

                    seq        <= seq + 1'b1;
                    byte_index   <= 5'd0;
                    sending      <= 1'b1;
                    byte_pending <= 1'b1;
                  end
                end else begin
                    decim_count <= decim_count + 1'b1;
                end
            end

            if (sending) begin
                //hand the next byte over once the transmitter is free
                if (byte_pending && !tx_busy && !tx_start) begin
                    tx_byte      <= pkt[byte_index];
                    tx_start     <= 1'b1;
                    byte_pending <= 1'b0;
                end

                //and separately, notice when one has finished going out
                if (tx_done) begin
                    if (byte_index == PACKET_LEN - 1) begin
                        sending     <= 1'b0;
                        packet_sent <= 1'b1;
                    end else begin
                        byte_index   <= byte_index + 1'b1;
                        byte_pending <= 1'b1;
                    end
                end
            end
        end
    end

endmodule