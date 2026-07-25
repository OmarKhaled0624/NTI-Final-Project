module tb_Master_I2C;

    reg clk_i;
    reg rst_i;
    reg start;
    reg m_w_r_i;
    reg [6:0] slave_add;
    reg [7:0] data_in;

    wire [7:0] m_data_out;
    wire m_busy;
    wire m_data_ready;
    wire m_error;
    wire scl;
    wire sda;

    reg drive_sda;
    reg sda_val;
    assign sda = drive_sda ? sda_val : 1'bz;
    pullup(sda);

    reg [7:0] byte_from_master;
    reg [7:0] byte_to_master;
    integer i;

    Master_I2C dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .start(start),
        .m_w_r_i(m_w_r_i),
        .slave_add(slave_add),
        .data_in(data_in),
        .m_data_out(m_data_out),
        .m_busy(m_busy),
        .m_data_ready(m_data_ready),
        .m_error(m_error),
        .scl(scl),
        .sda(sda)
    );

    // 50 MHz clock
    always #5 clk_i = ~clk_i;

    // pretend to be a slave module at address 0x50
    initial begin
        drive_sda = 0;
        byte_to_master = 8'hA5;

        forever begin
            @(negedge sda);// start condition
            if (scl == 1) begin

                
                for (i = 7; i >= 0; i = i - 1) begin // address + read/write bit
                    @(posedge scl);
                    byte_from_master[i] = sda;
                end

                if (byte_from_master[7:1] == slave_add) begin
                    // send ack
                    @(negedge scl);
                    drive_sda = 1;
                    sda_val = 0;
                    @(posedge scl);
                    @(negedge scl);
                    drive_sda = 0;

                    if (byte_from_master[0] == 0) begin
                        // write
                        for (i = 7; i >= 0; i = i - 1) begin
                            @(posedge scl);
                            byte_from_master[i] = sda;
                        end
                        @(negedge scl);
                        drive_sda = 1;
                        sda_val = 0;
                        @(posedge scl);
                        @(negedge scl);
                        drive_sda = 0;
                    end
                    else begin
                        // read
                        for (i = 7; i >= 0; i = i - 1) begin
                            drive_sda = 1;
                            sda_val = byte_to_master[i];
                            @(posedge scl);
                            @(negedge scl);
                        end
                        drive_sda = 0;
                        @(posedge scl);
                        @(negedge scl);
                    end
                end
            end
        end
    end

    initial begin
        clk_i = 0;
        rst_i = 0;
        start = 0;
        m_w_r_i = 0;
        slave_add = 7'h50;
        data_in = 8'h00;

        #50;
        rst_i = 1;
        #50;

        // test 1: write 0x3C to the slave at 0x50
        slave_add = 7'h50;
        data_in = 8'h3C;
        m_w_r_i = 0;
        start = 1;
        #6000;
        start = 0;
        wait (m_data_ready == 1);
        #6000;

        // test 2: read a byte back from the slave at 0x50
        m_w_r_i = 1;
        start = 1;
        #6000;
        start = 0;
        wait (m_data_ready == 1);
        #6000;

        // test 3: talk to an address nobody answers, to see m_error go high
        slave_add = 7'h10;
        m_w_r_i = 0;
        data_in = 8'hFF;
        start = 1;
        #6000;
        start = 0;
        wait (m_data_ready == 1);
        #6000;

        $stop;
    end

endmodule
