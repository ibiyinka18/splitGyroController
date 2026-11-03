module imu_controller #(
    parameter    CLK_DIV = 6,
    parameter   [23:0]  SETTLE_CYCLES   = 24'd1_200_000,  //100 ms @ 12mhz (gyro will need 35ms)
    //12 MHz / 800 Hz. the imu is configured for an 800 Hz output data rate,
    //so poll at that rate instead of free-running. reading faster just
    //re-reads the same values and floods whatever is downstream
    parameter   [15:0]  SAMPLE_PERIOD   = 16'd15000
) (
    input wire   clk,
    input wire   rst_n,


    // to/from spi master

    output reg          spi_start,
    output reg  [7:0]   spi_tx_byte,
    output reg          spi_hold_cs,
    input wire  [7:0]   spi_rx_byte,
    input wire          spi_done,


    // sensnor outputs
    output reg signed [15:0] accel_x,
    output reg signed [15:0] accel_y,
    output reg signed [15:0] accel_z,
    output reg signed [15:0] gyro_x,
    output reg signed [15:0] gyro_y,
    output reg signed [15:0] gyro_z,
    output reg               data_valid// 1-clk pulsewhen a new set lands
);

    //ICM-45686 regitster map
    localparam [7:0]  REG_DATA_START  = 8'h00;
    localparam [7:0]  REG_PWR_MGMT0  = 8'h10;
    localparam [7:0]  REG_ACCEL_CONFIG0  = 8'h1B;
    localparam [7:0]  REG_GYRO_CONFIG0  = 8'h1C;

    //Configuration values
    localparam [7:0] VAL_PWR_MGMT0   = 8'h0F; // gyro +accel low noise
    localparam [7:0] VAL_ACCEL_CONFIG0   = 8'h26;  //+/-8g 800hz
    localparam [7:0] VAL_GYRO_CONFIG0   = 8'h16; //+-200 dps, 800 Hz

    localparam [7:0]  READ_BIT  = 8'h80; //OR into an address to read
    localparam [7:0]  N_DATA_BYTES  =5'd12; //6 axes x 2 bytes
  


    //state machine
    localparam [2:0] INIT_ADDR = 3'd0; // sending config register address
    localparam [2:0] INIT_DATA = 3'd1; // send its value
    localparam [2:0] SETTLE = 3'd2; // wait for it to stabalize
    localparam [2:0] CMD = 3'd3; // send 0x80 (read from 0x00)
    localparam [2:0] READ = 3'd4; //clock out 12 dummy bytes
    localparam [2:0] PUBLISH = 3'd5; // assmeble words, pulse data_valid
    localparam [2:0] WAIT_SAMPLE = 3'd6; // pace reads to the sensor's odr

    reg [2:0] state;
    reg [1:0] init_index; //which. of the three config registers
    reg [4:0] byte_index; // 0..1 during read
    reg [23:0] settle_count; // settle delay counter
    reg [15:0] sample_timer; // counts between reads
    reg [7:0]  data_buf [0:11]; // the 112 raw bytes as they arrive

    //picks which config register this init step writes.
    // combinatinal:explicitt sensitivity on intit_index only.
    reg [7:0] init_addr;
    reg [7:0] init_val;

    always@(init_index)begin
        case(init_index)
        2'd0:   begin init_addr = REG_PWR_MGMT0;    init_val = VAL_PWR_MGMT0; end
        2'd1:   begin init_addr = REG_GYRO_CONFIG0; init_val = VAL_GYRO_CONFIG0; end
        default: begin init_addr = REG_ACCEL_CONFIG0; init_val = VAL_ACCEL_CONFIG0; end
        endcase
    end



    reg pending; //1 = a spinbyte is currently in flight 
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state       <= INIT_ADDR;
            init_index  <= 2'd0;
            byte_index  <= 5'd0;
            settle_count <= 24'd0;
            sample_timer <= 16'd0;
            pending      <= 1'b0;
            spi_start    <= 1'b0;
            spi_tx_byte  <= 8'd0;
            spi_hold_cs <= 1'b0;
            data_valid  <= 1'b0;
            accel_x <= 16'd0; accel_y <=16'd0; accel_z<= 16'd0;
            gyro_x <= 16'd0; gyro_y <=16'd0; gyro_z <= 16'd0;

        end else begin
            spi_start <= 1'b0;
            data_valid <= 1'b0;

            //free-runs so the period is measured start-of-read to
            //start-of-read rather than read-end to read-start. CMD resets it,
            //and a later non-blocking assignment wins, so that reset holds
            sample_timer <= sample_timer + 1'b1;

            case (state)

            INIT_ADDR: begin
                if(!pending) begin
                    spi_tx_byte <= init_addr;
                    spi_hold_cs <=  1'b1;
                    spi_start <= 1'b1;
                    pending <= 1'b1;
                end else if (spi_done) begin
                    pending <= 1'b0;
                    state <= INIT_DATA;
                end
            end
            INIT_DATA : begin
                if(!pending) begin
                spi_tx_byte <= init_val;
                spi_hold_cs <= 1'b0;
                spi_start   <= 1'b1;
                pending     <= 1'b1;
            end else if (spi_done) begin
                pending <= 1'b0;
                if(init_index == 2'd2)
                state<= SETTLE;
                else begin
                    init_index <= init_index + 1'b1;
                    state      <= INIT_ADDR;
                end
            end
        end
                
           SETTLE: begin
            if(settle_count == SETTLE_CYCLES) begin
                settle_count <= 24'd0;
            sample_timer <= 16'd0;
                state        <= CMD;
            end else begin
                settle_count    <= settle_count + 1'b1;
            end
           end 
           CMD: begin
            if(!pending) begin
                sample_timer <= 16'd0;
                spi_tx_byte <= REG_DATA_START | READ_BIT;
                spi_hold_cs <= 1'b1;
                spi_start   <= 1'b1;
                pending     <= 1'b1;
            end else if (spi_done) begin
                pending <= 1'b0;
                byte_index <= 5'd0;
                state      <= READ;
            end
           end
           READ: begin
            if(!pending) begin
                spi_tx_byte <= 8'h00;
                spi_hold_cs <= (byte_index == N_DATA_BYTES-1)? 1'b0 : 1'b1;
                spi_start <=1'b1;
                pending   <= 1'b1;
            end else if(spi_done)begin
                data_buf[byte_index] <= spi_rx_byte;
                pending <=1'b0;
                if(byte_index == N_DATA_BYTES-1)
                state <= PUBLISH;
                else
                byte_index <= byte_index + 1'b1;
            end
           end
        
        PUBLISH: begin
            accel_x <= {data_buf[0], data_buf[1]};
            accel_y <= {data_buf[2], data_buf[3]};
            accel_z <= {data_buf[4], data_buf[5]};
            gyro_x <= {data_buf[6], data_buf[7]};
            gyro_y <= {data_buf[8], data_buf[9]};
            gyro_z <= {data_buf[10], data_buf[11]};
            data_valid <= 1'b1;
            state   <= WAIT_SAMPLE;
        end
        WAIT_SAMPLE: begin
            //hold off until one sample period has passed since the last read
            if (sample_timer == SAMPLE_PERIOD - 1) begin
                sample_timer <= 16'd0;
                state        <= CMD;
            end else begin
                sample_timer <= sample_timer + 1'b1;
            end
        end
    endcase
    end
    end


endmodule
