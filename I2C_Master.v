module Master_I2C(

    input wire clk_i, rst_i, start, m_w_r_i,
    input wire [6:0] slave_add,
    input wire [7:0] data_in,

    output reg [7:0] m_data_out,
    output reg m_busy, m_data_ready, m_error,
    output wire scl,
    inout wire sda
);

reg [3:0] state;
reg [7:0] shift_reg;
reg [2:0] bit_count;
reg sda_en, sda_out, scl_phase;
reg scl_tick_last;
reg scl_tick_rise;

wire scl_tick;

clk_divider divider(
    .clk_i(clk_i),
    .rst_i(rst_i),
    .scl_tick(scl_tick)
);

assign sda = sda_en ? sda_out : 1'bz;
assign scl = ~scl_phase;

always @(posedge clk_i or negedge rst_i) begin
    if (!rst_i) begin
        scl_tick_last <= 1'b0;
        scl_tick_rise <= 1'b0;
    end
    else begin
        if (scl_tick == 1'b1 && scl_tick_last == 1'b0)
            scl_tick_rise <= 1'b1;
        else
            scl_tick_rise <= 1'b0;

        scl_tick_last <= scl_tick;
    end
end


localparam idle = 4'b0000;
localparam start_cond = 4'b0001;
localparam load_addr = 4'b0010;
localparam send_addr = 4'b0011;
localparam addr_ack = 4'b0100;
localparam load_data = 4'b0101;
localparam load_recv = 4'b0110;
localparam rec_data = 4'b0111;
localparam send_data = 4'b1000;
localparam data_ack = 4'b1001;
localparam stop_cond = 4'b1010;
localparam done_state = 4'b1011;
localparam master_nack = 4'b1100;
localparam stop_hold = 4'b1101;


always @(posedge clk_i or negedge rst_i) begin
    if (!rst_i)begin
        state <= idle;
        m_busy <= 1'b0;
        m_data_ready <= 1'b0;
        m_error <= 1'b0;
        sda_out <= 1'b1;
        sda_en <= 1'b0;
        bit_count <= 3'b000;
        shift_reg <= 8'b00000000;
        m_data_out <= 8'b00000000;
        scl_phase <= 1'b0;

    end
    else begin
        if(scl_tick_rise) begin
            case(state)
                idle: begin
                    m_busy <= 1'b0;
                    m_data_ready <= 1'b0;
                    m_error <= 1'b0;
                    scl_phase <= 1'b0;
                    sda_en <= 1'b0;

                    if(start) begin
                        state <= start_cond;
                    end

                end

                start_cond: begin
                    m_busy <= 1'b1;
                    scl_phase <= 1'b0;
                    sda_en <= 1'b1;
                    sda_out <= 1'b0;

                    state <= load_addr;
                end

                load_addr: begin
                    shift_reg <= {slave_add, m_w_r_i};
                    bit_count <= 3'b111;
                    scl_phase <= 1'b0;
                    state <= send_addr;
                end

                send_addr: begin
                    if(scl_phase)begin
                        if (bit_count == 3'b000)begin
                            state <= addr_ack;
                        end
                        else begin
                            shift_reg <= shift_reg << 1;
                            bit_count <= bit_count - 1'b1;
                        end
                        scl_phase <= 1'b0;
                    end
                    else begin
                        sda_en <= 1'b1;
                        sda_out <= shift_reg[7];
                        scl_phase <= 1'b1;
                    end
                end

                addr_ack: begin
                    if (scl_phase) begin
                        if (sda)begin
                            m_error <= 1'b1;
                            state <= stop_cond;
                        end
                        else begin
                            if(m_w_r_i)begin
                                state <= load_recv;
                            end
                            else begin
                                state <= load_data;
                            end
                        end
                        scl_phase <= 1'b0;
                    end
                    else begin
                        sda_en <= 1'b0;
                        scl_phase <= 1'b1;
                    end
                end

                load_data: begin
                    shift_reg <= data_in;
                    bit_count <= 3'b111;
                    scl_phase <= 1'b0;
                    state <= send_data;
                end

                load_recv: begin
                    bit_count <= 3'b111;
                    sda_en <= 1'b0;
                    scl_phase <= 1'b0;
                    state <= rec_data;
                end

                rec_data: begin
                    sda_en <= 1'b0;
                    if (scl_phase)begin
                        shift_reg[bit_count] <= sda;
                        if (bit_count == 3'b000)begin
                            state <= master_nack;
                        end
                        else begin
                            bit_count <= bit_count - 1'b1;
                        end
                        scl_phase <= 1'b0;
                    end
                    else begin
                        scl_phase <= 1'b1;
                    end
                end

                master_nack: begin
                    if (scl_phase)begin
                        m_data_out <= shift_reg;
                        state <= stop_cond;
                        scl_phase <= 1'b0;
                    end
                    else begin
                        sda_en <= 1'b1;
                        sda_out <= 1'b1;
                        scl_phase <= 1'b1;
                    end
                end

                send_data: begin
                    if(scl_phase)begin
                        if (bit_count == 3'b000)begin
                            state <= data_ack;
                        end
                        else begin
                            shift_reg <= shift_reg << 1;
                            bit_count <= bit_count - 1'b1;
                        end
                        scl_phase <= 1'b0;
                    end
                    else begin
                        sda_en <= 1'b1;
                        sda_out <= shift_reg[7];
                        scl_phase <= 1'b1;
                    end
                end

                data_ack: begin
                    if (scl_phase) begin
                        if(sda == 1'b1)begin
                            m_error <= 1'b1;
                        end
                        state <= stop_cond;
                        scl_phase <= 1'b0;
                    end
                    else begin
                        sda_en <= 1'b0;
                        scl_phase <= 1'b1;
                    end
                end

                stop_cond: begin
                    if (scl_phase) begin
                        state <= stop_hold;
                        scl_phase <= 1'b0;
                    end
                    else begin
                        sda_en <= 1'b1;
                        sda_out <= 1'b0;
                        scl_phase <= 1'b1;
                    end
                end

                stop_hold: begin
                    sda_out <= 1'b1;
                    state <= done_state;
                end

                done_state: begin
                    m_busy <= 1'b0;
                    m_data_ready <= 1'b1;
                    state <= idle;
                end

                default: state <= idle;

            endcase
        end
    end
end


endmodule


module clk_divider (
    input wire clk_i, 
    input wire rst_i,
    output reg scl_tick,
    output wire scl
); 

    localparam DIVIDER = 250;
    reg [7:0] count; 


    always @(posedge clk_i or negedge rst_i) begin
        if (!rst_i) begin
            count    <= 0;
            scl_tick <= 1'b0;
        end
        else begin
            
            if (count == 249) begin 
                count    <= 0;
                scl_tick <= ~scl_tick;
            end
            else begin
                count <= count + 1;
            end
        end
    end

    assign scl = scl_tick;

endmodule
