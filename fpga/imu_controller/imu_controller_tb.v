`timescale 1ns/1ps
//
// Integration testbench: imu_controller + spi_master + behavioural ICM-45686.
//
// Unlike spi_master_tb (which tests one module against a dumb byte echo),
// this wires BOTH real modules together and talks to a slave model that
// actually decodes the SPI register protocol. It proves:
//
//   1. the three config registers are written with the correct values
//   2. the data read is issued as ONE CS-low burst, not 13 transactions
//   3. the 12 returned bytes land in the correct axis outputs, MSB first
//
module imu_controller_tb;

    localparam CLK_PERIOD = 83.333;      // 12 MHz, matches the iCEstick

    reg clk = 1'b0;
    reg rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- imu_controller <-> spi_master ----
    wire       spi_start;
    wire [7:0] spi_tx_byte;
    wire       spi_hold_cs;
    wire [7:0] spi_rx_byte;
    wire       spi_done;
    wire       spi_busy;

    // ---- spi_master <-> IMU pins ----
    wire sclk, cs_n, mosi;
    reg  miso;

    // ---- sensor outputs ----
    wire signed [15:0] accel_x, accel_y, accel_z;
    wire signed [15:0] gyro_x,  gyro_y,  gyro_z;
    wire               data_valid;

    // ---------------------------------------------------------------
    // Device under test: both real modules, wired as they will be in top.v
    // ---------------------------------------------------------------
    imu_controller #(
        .SETTLE_CYCLES (24'd50)          // shortened; hardware still uses 100 ms
    ) ctrl (
        .clk         (clk),
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
        .data_valid  (data_valid)
    );

    spi_master #(
        .CLK_DIV (6)
    ) spi (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (spi_start),
        .hold_cs (spi_hold_cs),
        .tx_byte (spi_tx_byte),
        .rx_byte (spi_rx_byte),
        .busy    (spi_busy),
        .done    (spi_done),
        .sclk    (sclk),
        .cs_n    (cs_n),
        .mosi    (mosi),
        .miso    (miso)
    );

    // ---------------------------------------------------------------
    // Behavioural ICM-45686 slave model
    //
    // Decodes the register protocol from section 10.5 of DS-000577:
    //   byte 1 = R/W bit (1 = read) + 7 address bits
    //   byte 2+ = data, with the address auto-incrementing on a burst
    // ---------------------------------------------------------------
    reg [7:0] regfile [0:127];

    reg [7:0] slave_rx;          // byte being shifted in from MOSI
    reg [7:0] slave_tx;          // byte being shifted out on MISO
    reg [3:0] slave_bit;         // bit position within the current byte
    reg [4:0] slave_byte;        // which byte of this transaction
    reg       slave_rw;          // 1 = this transaction is a read
    reg [6:0] slave_addr;        // current register address
    reg [7:0] full_byte;         // combinational helper

    integer i;
    initial begin
        for (i = 0; i < 128; i = i + 1) regfile[i] = 8'h00;

        // Distinctive data so a mis-ordered byte is immediately obvious
        // little endian, as the real device actually returns it (datasheet
        // section 15) - low byte at the lower address
        regfile[8'h00] = 8'h22;  regfile[8'h01] = 8'h11;   // accel_x = 0x1122
        regfile[8'h02] = 8'h44;  regfile[8'h03] = 8'h33;   // accel_y = 0x3344
        regfile[8'h04] = 8'h66;  regfile[8'h05] = 8'h55;   // accel_z = 0x5566
        regfile[8'h06] = 8'h88;  regfile[8'h07] = 8'h77;   // gyro_x  = 0x7788
        regfile[8'h08] = 8'hAA;  regfile[8'h09] = 8'h99;   // gyro_y  = 0x99AA
        regfile[8'h0A] = 8'hCC;  regfile[8'h0B] = 8'hBB;   // gyro_z  = 0xBBCC

        slave_rx   = 8'h00;
        slave_tx   = 8'h00;
        slave_bit  = 4'd0;
        slave_byte = 5'd0;
        slave_rw   = 1'b0;
        slave_addr = 7'h00;
        miso       = 1'b0;
    end

    // A new transaction begins when CS falls
    always @(negedge cs_n) begin
        slave_bit  <= 4'd0;
        slave_byte <= 5'd0;
    end

    // Sample MOSI on the rising edge (datasheet: data latched on rising SCLK)
    always @(posedge sclk) if (!cs_n) begin
        full_byte = {slave_rx[6:0], mosi};
        slave_rx <= full_byte;

        if (slave_bit == 4'd7) begin
            slave_bit <= 4'd0;
            if (slave_byte == 5'd0) begin
                // Command byte: top bit is R/W, low 7 are the address
                slave_rw   <= full_byte[7];
                slave_addr <= full_byte[6:0];
            end else begin
                // Data byte: store it on a write, then auto-increment
                if (!slave_rw) regfile[slave_addr] <= full_byte;
                slave_addr <= slave_addr + 1'b1;
            end
            slave_byte <= slave_byte + 1'b1;
        end else begin
            slave_bit <= slave_bit + 1'b1;
        end
    end

    // Drive MISO on the falling edge (datasheet: data transitions on falling)
    always @(negedge sclk) if (!cs_n) begin
        if (slave_bit == 4'd0) begin
            // Byte boundary: present the MSB of the register being read
            miso     <= regfile[slave_addr][7];
            slave_tx <= {regfile[slave_addr][6:0], 1'b0};
        end else begin
            miso     <= slave_tx[7];
            slave_tx <= {slave_tx[6:0], 1'b0};
        end
    end

    // ---------------------------------------------------------------
    // Waveform dump
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("imu_controller_tb.vcd");
        $dumpvars(0, imu_controller_tb);
    end

    // ---------------------------------------------------------------
    // Checks
    // ---------------------------------------------------------------
    integer errors = 0;

    task check8(input [127:0] name, input [7:0] got, input [7:0] want);
        begin
            if (got !== want) begin
                $display("  FAIL  %0s = 0x%02h (expected 0x%02h)", name, got, want);
                errors = errors + 1;
            end else begin
                $display("  pass  %0s = 0x%02h", name, got);
            end
        end
    endtask

    task check16(input [127:0] name, input signed [15:0] got, input [15:0] want);
        begin
            if (got !== want) begin
                $display("  FAIL  %0s = 0x%04h (expected 0x%04h)", name, got, want);
                errors = errors + 1;
            end else begin
                $display("  pass  %0s = 0x%04h", name, got);
            end
        end
    endtask

    // CS must stay low for the whole 13-byte burst. Watch for it bouncing
    // while the controller is in its READ state -- but NOT on the final byte,
    // where releasing CS is the correct end-of-burst behaviour.
    integer cs_rises_during_read = 0;
    always @(posedge cs_n)
        if (ctrl.state == 3'd4 && ctrl.byte_index < 5'd11)
            cs_rises_during_read = cs_rises_during_read + 1;

    initial begin
        rst_n = 1'b0;
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        // Wait for the first complete sensor reading
        @(posedge data_valid);
        @(negedge clk);

        $display("");
        $display("  --- configuration registers ---");
        check8("PWR_MGMT0    (0x10)", regfile[8'h10], 8'h0F);
        check8("GYRO_CONFIG0 (0x1C)", regfile[8'h1C], 8'h16);
        check8("ACCEL_CONFIG0(0x1B)", regfile[8'h1B], 8'h26);

        $display("");
        $display("  --- sensor outputs ---");
        check16("accel_x", accel_x, 16'h1122);
        check16("accel_y", accel_y, 16'h3344);
        check16("accel_z", accel_z, 16'h5566);
        check16("gyro_x ", gyro_x,  16'h7788);
        check16("gyro_y ", gyro_y,  16'h99AA);
        check16("gyro_z ", gyro_z,  16'hBBCC);

        $display("");
        $display("  --- burst integrity ---");
        if (cs_rises_during_read != 0) begin
            $display("  FAIL  cs_n went high %0d time(s) mid-burst", cs_rises_during_read);
            errors = errors + 1;
        end else begin
            $display("  pass  cs_n held low for the whole burst");
        end

        // Second reading, to prove it loops rather than stopping after one
        @(posedge data_valid);
        @(negedge clk);
        $display("");
        $display("  --- second reading (loop check) ---");
        check16("accel_x", accel_x, 16'h1122);
        check16("gyro_z ", gyro_z,  16'hBBCC);

        $display("");
        if (errors == 0) $display("  *** ALL CHECKS PASS ***");
        else             $display("  *** %0d CHECK(S) FAILED ***", errors);
        $display("");
        $finish;
    end

    // Safety net: never let a broken handshake hang the simulation
    initial begin
        #5_000_000;
        $display("");
        $display("  *** TIMEOUT -- state=%0d byte_index=%0d pending=%b ***",
                 ctrl.state, ctrl.byte_index, ctrl.pending);
        $display("");
        $finish;
    end

endmodule