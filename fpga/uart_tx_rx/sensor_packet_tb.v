`timescale 1ns/1ps
/* End to end check of sensor_packet + uart_tx.

The testbench decodes the serial line the way a real receiver would - wait for
the falling start bit, skip to the middle of the first data bit, then sample
every bit period - so this exercises the actual bit timing rather than just
the packet logic.

Checks the sync pattern, the sequence counter, the payload bytes, the
checksum, and that decimation holds the output to one packet per DECIMATE
samples.
*/
module sensor_packet_tb;

    localparam CLK_PERIOD   = 83.333;              //12 MHz
    localparam CLKS_PER_BIT = 104;                 //115200 baud
    localparam BIT_TIME     = CLKS_PER_BIT * CLK_PERIOD;
    localparam DECIMATE     = 4;
    localparam PACKET_LEN   = 21;

    reg clk = 1'b0;
    reg rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg sample_valid;
    reg signed [15:0] accel_x, accel_y, accel_z;
    reg signed [15:0] gyro_x, gyro_y, gyro_z;
    reg signed [15:0] pitch, roll;
    reg calibrated, is_still;

    wire [7:0] tx_byte;
    wire       tx_start, tx_busy, tx_done, tx_serial, dropped;

    sensor_packet #(.DECIMATE(DECIMATE)) pk (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(sample_valid),
        .accel_x(accel_x), .accel_y(accel_y), .accel_z(accel_z),
        .gyro_x(gyro_x),   .gyro_y(gyro_y),   .gyro_z(gyro_z),
        .pitch(pitch),     .roll(roll),
        .calibrated(calibrated), .is_still(is_still),
        .tx_byte(tx_byte), .tx_start(tx_start),
        .tx_busy(tx_busy), .tx_done(tx_done),
        .dropped(dropped)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx (
        .clk(clk), .rst_n(rst_n),
        .tx_start(tx_start), .tx_byte(tx_byte),
        .tx_serial(tx_serial), .tx_busy(tx_busy), .tx_done(tx_done)
    );

    integer errors = 0;
    reg [7:0] rx [0:PACKET_LEN-1];

    initial begin
        $dumpfile("sensor_packet_tb.vcd");
        $dumpvars(0, sensor_packet_tb);
    end

    //decode one byte off the wire exactly as a real receiver would
    task uart_rx_byte(output reg [7:0] b);
        integer i;
        begin
            @(negedge tx_serial);              //start bit
            #(BIT_TIME * 1.5);                 //land in the middle of bit 0
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = tx_serial;              //lsb first
                #(BIT_TIME);
            end
        end
    endtask

    task receive_packet;
        integer i;
        begin
            for (i = 0; i < PACKET_LEN; i = i + 1) uart_rx_byte(rx[i]);
        end
    endtask

    //one sample pulse into the packetiser
    task pulse_sample;
        begin
            @(negedge clk);
            sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task expect8(input [255:0] name, input [7:0] got, input [7:0] want);
        begin
            if (got !== want) begin
                $display("  FAIL  %0s: got 0x%02h, expected 0x%02h", name, got, want);
                errors = errors + 1;
            end else begin
                $display("  pass  %0s: 0x%02h", name, got);
            end
        end
    endtask

    reg [7:0] expected_sum;
    integer k;

    initial begin
        rst_n        = 1'b0;
        sample_valid = 1'b0;
        accel_x = 16'sh1122;  accel_y = 16'sh3344;  accel_z = 16'sh5566;
        gyro_x  = 16'sh7788;  gyro_y  = 16'sh99AA;  gyro_z  = 16'shBBCC;
        pitch   = 16'sh0102;  roll    = 16'sh0304;
        calibrated = 1'b1;    is_still = 1'b0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        //DECIMATE samples should produce exactly one packet
        fork
            begin
                for (k = 0; k < DECIMATE; k = k + 1) begin
                    pulse_sample;
                    repeat (15000) @(negedge clk);
                end
            end
            receive_packet;
        join

        $display("");
        $display("  --- framing ---");
        expect8("sync0", rx[0], 8'hAA);
        expect8("sync1", rx[1], 8'h55);
        expect8("seq",   rx[2], 8'h00);
        expect8("status (calibrated set)", rx[3], 8'h01);

        $display("");
        $display("  --- payload ---");
        expect8("accel_x hi", rx[4],  8'h11);
        expect8("accel_x lo", rx[5],  8'h22);
        expect8("accel_z hi", rx[8],  8'h55);
        expect8("gyro_x hi",  rx[10], 8'h77);
        expect8("gyro_z lo",  rx[15], 8'hCC);
        expect8("pitch hi",   rx[16], 8'h01);
        expect8("roll lo",    rx[19], 8'h04);

        $display("");
        $display("  --- checksum ---");
        expected_sum = 8'h00;
        for (k = 2; k < PACKET_LEN - 1; k = k + 1)
            expected_sum = expected_sum ^ rx[k];
        expect8("xor over bytes 2..19", rx[20], expected_sum);

        //second packet: sequence must advance and new data must appear
        accel_x  = 16'shDEAD;
        is_still = 1'b1;

        fork
            begin
                for (k = 0; k < DECIMATE; k = k + 1) begin
                    pulse_sample;
                    repeat (15000) @(negedge clk);
                end
            end
            receive_packet;
        join

        $display("");
        $display("  --- second packet ---");
        expect8("sync0",       rx[0], 8'hAA);
        expect8("seq advanced", rx[2], 8'h01);
        expect8("status (both set)", rx[3], 8'h03);
        expect8("accel_x hi updated", rx[4], 8'hDE);
        expect8("accel_x lo updated", rx[5], 8'hAD);

        $display("");
        if (errors == 0) $display("  *** ALL CHECKS PASS ***");
        else             $display("  *** %0d CHECK(S) FAILED ***", errors);
        $display("");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("  *** TIMEOUT  sending=%b byte_index=%0d ***", pk.sending, pk.byte_index);
        $finish;
    end

endmodule
