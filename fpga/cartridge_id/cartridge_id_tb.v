`timescale 1ns/1ps
/* Checks cartridge_id debounces insertion properly.

The interesting cases are not the steady states, they are the messy ones:
contacts chattering during insertion, a brief glitch that should be ignored
entirely, and a swap going via the unplugged state.

DEBOUNCE_CYCLES is shortened here so the simulation stays quick; the logic is
identical at the 600000 used in hardware.
*/
module cartridge_id_tb;

    localparam CLK_PERIOD = 83.333;
    localparam DEB        = 200;        //short, for sim speed

    localparam [2:0] ID_NONE     = 3'b111;
    localparam [2:0] ID_JOYSTICK = 3'b110;
    localparam [2:0] ID_DPAD     = 3'b101;

    reg clk = 1'b0;
    reg rst_n;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg  [2:0] id_pins;
    wire [2:0] cart_id;
    wire       cart_present, cart_changed;

    cartridge_id #(.DEBOUNCE_CYCLES(DEB)) dut (
        .clk(clk), .rst_n(rst_n),
        .id_pins(id_pins),
        .cart_id(cart_id),
        .cart_present(cart_present),
        .cart_changed(cart_changed)
    );

    integer errors = 0;
    integer change_count = 0;

    always @(posedge clk) if (cart_changed) change_count = change_count + 1;

    initial begin
        $dumpfile("cartridge_id_tb.vcd");
        $dumpvars(0, cartridge_id_tb);
    end

    task expect_id(input [255:0] name, input [2:0] want, input present);
        begin
            if (cart_id !== want || cart_present !== present) begin
                $display("  FAIL  %0s: id=%b present=%b (expected %b / %b)",
                         name, cart_id, cart_present, want, present);
                errors = errors + 1;
            end else begin
                $display("  pass  %0s: id=%b present=%b", name, cart_id, cart_present);
            end
        end
    endtask

    //chatter between the old and new value, as contacts actually do
    task bounce(input [2:0] from, input [2:0] to, input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                id_pins = (i % 2) ? to : from;
                repeat (DEB/4) @(posedge clk);
            end
            id_pins = to;
        end
    endtask

    initial begin
        rst_n   = 1'b0;
        id_pins = ID_NONE;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (DEB*2) @(posedge clk);

        $display("");
        $display("  --- nothing inserted ---");
        expect_id("idle reads none", ID_NONE, 1'b0);

        $display("");
        $display("  --- insert joystick, with contact bounce ---");
        bounce(ID_NONE, ID_JOYSTICK, 6);
        repeat (DEB*2) @(posedge clk);
        expect_id("settles on joystick", ID_JOYSTICK, 1'b1);
        if (change_count != 1) begin
            $display("  FAIL  bounce produced %0d change pulses, expected 1", change_count);
            errors = errors + 1;
        end else $display("  pass  exactly one cart_changed pulse despite bouncing");

        $display("");
        $display("  --- a glitch shorter than the debounce is ignored ---");
        change_count = 0;
        id_pins = ID_DPAD;
        repeat (DEB/2) @(posedge clk);     //too brief to count
        id_pins = ID_JOYSTICK;
        repeat (DEB*2) @(posedge clk);
        expect_id("still joystick", ID_JOYSTICK, 1'b1);
        if (change_count != 0) begin
            $display("  FAIL  glitch produced %0d change pulses, expected 0", change_count);
            errors = errors + 1;
        end else $display("  pass  no spurious cart_changed");

        $display("");
        $display("  --- swap to dpad via unplugged ---");
        change_count = 0;
        bounce(ID_JOYSTICK, ID_NONE, 4);
        repeat (DEB*2) @(posedge clk);
        expect_id("reads none while out", ID_NONE, 1'b0);

        bounce(ID_NONE, ID_DPAD, 4);
        repeat (DEB*2) @(posedge clk);
        expect_id("settles on dpad", ID_DPAD, 1'b1);
        if (change_count != 2) begin
            $display("  FAIL  swap produced %0d change pulses, expected 2", change_count);
            errors = errors + 1;
        end else $display("  pass  two cart_changed pulses, out then in");

        $display("");
        if (errors == 0) $display("  *** ALL CHECKS PASS ***");
        else             $display("  *** %0d CHECK(S) FAILED ***", errors);
        $display("");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("  *** TIMEOUT ***");
        $finish;
    end

endmodule
