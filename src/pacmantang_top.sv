//
// pacmantang top level
// nand2mario
//

// `timescale 1ns / 100ps

import configPackage::*;

module pacmantang_top (
    input sys_clk,

    // Button S1 and pin 48 are both resets
    input s1,
    input reset2,

    // UART
    input UART_RXD,
    output UART_TXD,

    // LEDs
    output [1:0] led,

    // SDRAM - Tang SDRAM pmod 1.2 for primer 25k, on-chip 32-bit 8MB SDRAM for nano 20k
    output O_sdram_clk,
    output O_sdram_cke,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [SDRAM_DATA_WIDTH-1:0] IO_sdram_dq,      // bidirectional data bus
    output [SDRAM_ROW_WIDTH-1:0] O_sdram_addr,     // multiplexed address bus
    output [1:0] O_sdram_ba,        // two banks
    output [SDRAM_DATA_WIDTH/8-1:0] O_sdram_dqm,    

    // MicroSD
    output sd_clk,
    inout  sd_cmd,      // MOSI
    input  sd_dat0,     // MISO
    output sd_dat1,     // 1
    output sd_dat2,     // 1
    output sd_dat3,     // 1

    // SPI flash
    output flash_spi_cs_n,          // chip select
    input flash_spi_miso,           // master in slave out
    output flash_spi_mosi,          // mster out slave in
    output flash_spi_clk,           // spi clock
    output flash_spi_wp_n,          // write protect
    output flash_spi_hold_n,        // hold operations

`ifdef CONTROLLER_SNES
    // snes controllers
    output joy1_strb,
    output joy1_clk,
    input joy1_data,
    output joy2_strb,
    output joy2_clk,
    input joy2_data,
`endif

`ifdef CONTROLLER_DS2
    // dualshock controllers
    output ds_clk,
    input ds_miso,
    output ds_mosi,
    output ds_cs,
    output ds_clk2,
    input ds_miso2,
    output ds_mosi2,
    output ds_cs2,
`endif

    // HDMI TX
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

// Core settings
wire arm_reset = 0;
wire [1:0] system_type;
wire pal_video = 0;
wire [1:0] scanlines = 2'b0;
wire joy_swap = 0;
wire mirroring_osd = 0;
wire overscan_osd = 0;
wire famicon_kbd = 0;
wire [3:0] palette_osd = 0;
wire [2:0] diskside_osd = 0;
wire blend = 0;
wire bk_save = 0;

// iosys softcore
wire        rv_valid;
reg         rv_ready;
wire [22:0] rv_addr;
wire [31:0] rv_wdata;
wire [3:0]  rv_wstrb;
reg  [15:0] rv_dout0;
wire [31:0] rv_rdata = {rv_dout, rv_dout0};
reg         rv_valid_r;
reg         rv_word;           // which word
reg         rv_req;
wire        rv_req_ack;
wire [15:0] rv_dout;
reg [1:0]   rv_ds;
reg         rv_new_req;

// Controller
wire [7:0] joy_rx[0:1], joy_rx2[0:1];     // 6 RX bytes for all button/axis state
wire [7:0] usb_btn, usb_btn2;
wire usb_btn_x, usb_btn_y, usb_btn_x2, usb_btn_y2;
wire usb_conerr, usb_conerr2;
wire auto_a, auto_b, auto_a2, auto_b2;

// OR together when both SNES and DS2 controllers are connected (right now only nano20k supports both simultaneously)
wor [11:0] joy1_btns, joy2_btns;    // SNES layout (R L X A RT LT DN UP START SELECT Y B)
                                    // Lower 8 bits are NES buttons

// NES gamepad
wire [7:0]NES_gamepad_button_state;
wire NES_gamepad_data_available;
wire [7:0]NES_gamepad_button_state2;
wire NES_gamepad_data_available2;

///////////////////////////
// PACMAN_WRAPPER
//////////////////////////
wire    [0:0]   pacman_enable = joy1_btns[2] & joy1_btns[5]; 
pacman_wrapper pacman_inst(
    .clk(sys_clk),
    .i_reset(~sys_resetn),
    .i_ce(pacman_enable),
    .i_nes_btn(joy1_btns),
    .tmds_clk_n(tmds_clk_n),
    .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n),
    .tmds_d_p(tmds_d_p),
    .overlay(overlay),
    .overlay_x(overlay_x),
    .overlay_y(overlay_y),
    .overlay_color(overlay_color)
);

///////////////////////////
// Clocks
///////////////////////////

wire clk;       // 21.477Mhz main clock
wire fclk;      // 3x clk SDRAM clock
wire hclk;      // 720p pixel clock: 74.25 Mhz
wire hclk5;     // 5x pixel clock: 371.25 Mhz
wire clk27;     // 27Mhz to generate hclk/hclk5
wire clk_usb;   // 12Mhz USB clock

reg sys_resetn = 0;
reg [7:0] reset_cnt = 255;      // reset for 255 cycles before start everything
always @(posedge clk) begin
    reset_cnt <= reset_cnt == 0 ? 0 : reset_cnt - 1;
    if (reset_cnt == 0)
//    if (reset_cnt == 0 && s1)     // for nano
        sys_resetn <= ~(joy1_btns[5] && joy1_btns[3]);    //  Select + Up
end

`ifndef VERILATOR
// sys_clk 27Mhz
assign clk27 = sys_clk;       // Nano20K: native 27Mhz system clock
gowin_pll_pacman pll_pacman(.clkin(sys_clk), .clkoutd3(clk), .clkout(fclk), .clkoutp(O_sdram_clk));

`else   // verilator

// dummy clocks for verilator
assign clk = sys_clk;
assign fclk = sys_clk;

`endif  // verilator

wire [31:0] status;

// From sdram_pacman.v
wire rv_address_is_wram = (rv_addr >= 'h66000)&&(rv_addr <= 'h68000);
wire rv_address_is_wram_66000 = rv_addr == 'h66000;
sdram_pacman sdram (
    .clk(fclk), .clkref(clkref), .resetn(sys_resetn), .busy(sdram_busy),

    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba), 
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n), 
    .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm), 

    // Free
    .addrA(), 
    .weA(), 
    .dinA(),
    .oeA(), 
    .doutA(),

    // PacMan
    .addrB(memory_addr_cpu),
    .weB(memory_write_cpu),
    .dinB(memory_dout_cpu),
    .oeB(memory_read_cpu),
    .doutB(memory_din_cpu),

    // IOSys risc-v softcore
    .rv_addr({rv_addr[20:2], rv_word}), 
    .rv_addr_wram(rv_address_is_wram ? rv_addr[15:0]: 16'h0),
    .rv_din(rv_word ? rv_wdata[31:16] : rv_wdata[15:0]), 
    .rv_ds(rv_ds), .rv_dout(rv_dout), .rv_req(rv_req), .rv_req_ack(rv_req_ack), .rv_we(rv_wstrb != 0),

    // Debug
    .dbg_leds(led)

);

///////////////////////////
// Peripherals
///////////////////////////

`ifdef VERILATOR

// For verilator, the only peripheral is the compiled-in game data 
GameData game_data(
    .clk(clk), .reset(~sys_resetn), .downloading(loading), 
    .odata(loader_do), .odata_clk(loader_do_valid));

`else

// For physical board, there's HDMI, iosys, joypads, and USB
wire overlay;                   // iosys controls overlay
wire [10:0] overlay_x;
wire [9:0]  overlay_y;
wire [15:0] overlay_color;      // BGR5

// IOSys for menu, rom loading...
localparam RV_IDLE_REQ0 = 3'd0;
localparam RV_WAIT0_REQ1 = 3'd1;
localparam RV_DATA0 = 3'd2;
localparam RV_WAIT1 = 3'd3;
localparam RV_DATA1 = 3'd4;
reg [2:0]   rvst;

always @(posedge clk) begin            // RV
    if (~sys_resetn) begin
        rvst <= RV_IDLE_REQ0;
        rv_ready <= 0;
    end else begin
        reg write = rv_wstrb != 0;
        reg rv_new_req_t = rv_valid & ~rv_valid_r;
        if (rv_new_req_t) rv_new_req <= 1;

        rv_ready <= 0;
        rv_valid_r <= rv_valid;

        case (rvst)
        RV_IDLE_REQ0: if (rv_new_req || rv_new_req_t) begin
            rv_new_req <= 0;
            rv_req <= ~rv_req;
            if (write && rv_wstrb[1:0] == 2'b0) begin
                // shortcut for only writing the upper word
                rv_word <= 1;
                rv_ds <= rv_wstrb[3:2];
                rvst <= RV_WAIT1;
            end else begin
                rv_word <= 0;
                if (write)
                    rv_ds <= rv_wstrb[1:0];
                else
                    rv_ds <= 2'b11;
                rvst <= RV_WAIT0_REQ1;
            end
        end

        RV_WAIT0_REQ1: begin
            if (rv_req == rv_req_ack) begin
                rv_req <= ~rv_req;      // request 1
                rv_word <= 1;
                if (write) begin
                    rvst <= RV_WAIT1;
                    if (rv_wstrb[3:2] == 2'b0) begin
                        // shortcut for only writing the lower word
                        rv_req <= rv_req;
                        rv_ready <= 1;
                        rvst <= RV_IDLE_REQ0;
                    end
                    rv_ds <= rv_wstrb[3:2];
                end else begin
                    rv_ds <= 2'b11;
                    rvst <= RV_DATA0;
                end
            end
        end

        RV_DATA0: begin
            rv_dout0 <= rv_dout;
            rvst <= RV_WAIT1;
        end
            
        RV_WAIT1: 
            if (rv_req == rv_req_ack) begin
                if (write)  begin
                    rv_ready <= 1;
                    rvst <= RV_IDLE_REQ0;
                end else
                    rvst <= RV_DATA1;
            end

        RV_DATA1: begin
            rv_ready <= 1;
            rvst <= RV_IDLE_REQ0;
        end

        default:;
        endcase
    end
end

localparam CORE_ID_PACMAN = 4;
iosys #(.COLOR_LOGO(15'b01100_00000_01000), .CORE_ID(CORE_ID_PACMAN) )     // purple pacmantang logo
    iosys (
    .clk(clk), .hclk(hclk), .resetn(sys_resetn),

    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color),
    .joy1(joy1_btns), .joy2(joy2_btns),

    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid), 
    .ram_busy(sdram_busy),

    .rv_valid(rv_valid), .rv_ready(rv_ready), .rv_addr(rv_addr),
    .rv_wdata(rv_wdata), .rv_wstrb(rv_wstrb), .rv_rdata(rv_rdata),

    .flash_spi_cs_n(flash_spi_cs_n), .flash_spi_miso(flash_spi_miso),
    .flash_spi_mosi(flash_spi_mosi), .flash_spi_clk(flash_spi_clk),
    .flash_spi_wp_n(flash_spi_wp_n), .flash_spi_hold_n(flash_spi_hold_n),

    .uart_tx(UART_TXD), .uart_rx(UART_RXD),

    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1),
    .sd_dat2(sd_dat2), .sd_dat3(sd_dat3),
    .o_reg_enhanced_apu(NES_enhanced_APU),
    // Wishbone master
    .i_wb_ack(),
    .i_wb_stall(),
    .i_wb_idata(),
    .i_wb_err(),
	.o_wb_cyc(),
    .o_wb_stb(),
    .o_wb_we(),
    .o_wb_err(),
    .o_wb_addr(),
    .o_wb_odata(),
    .o_wb_sel(),

    // Cheats
    .o_cheats_enabled(),
    .o_cheats_loaded(),

    // Debug LED
    .o_dbg_led(),

    // System Type
    .o_sys_type(),
    
    // Aspect Ratio
    .o_reg_aspect_ratio()
);

// Controller input
`ifdef CONTROLLER_SNES
controller_snes joy1_snes (
    .clk(clk), .resetn(sys_resetn), .buttons(joy1_btns),
    .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
);
controller_snes joy2_snes (
    .clk(clk), .resetn(sys_resetn), .buttons(joy2_btns),
    .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
);
`endif

`ifdef CONTROLLER_DS2
controller_ds2 joy1_ds2 (
    .clk(clk), .snes_buttons(joy1_btns),
    .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs) 
);
controller_ds2 joy2_ds2 (
   .clk(clk), .snes_buttons(joy2_btns),
   .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2) 
);
`endif

// Joypad handling
reg [7:0] joypad_bits, joypad_bits2;
reg [1:0] last_joypad_clock;
wire [2:0] joypad_out;
wire joypad_strobe = joypad_out[0];
wire [1:0] joypad_clock;
wire [4:0] joypad1_data, joypad2_data;
always @(posedge clk) begin
    if (joypad_strobe) begin
        joypad_bits <= {joy1_btns[7:2], joy1_btns[1] | auto_b, joy1_btns[0] | auto_a};;
        joypad_bits2 <= {joy2_btns[7:2], joy2_btns[1] | auto_b2, joy2_btns[0] | auto_a2};
    end
    if (!joypad_clock[0] && last_joypad_clock[0])
        joypad_bits <= {1'b1, joypad_bits[7:1]};
    if (!joypad_clock[1] && last_joypad_clock[1])
        joypad_bits2 <= {1'b1, joypad_bits2[7:1]};
    last_joypad_clock <= joypad_clock;
end
assign joypad1_data[0] = joypad_bits[0];
assign joypad2_data[0] = joypad_bits2[0];

`endif

reg [23:0] led_cnt;
always @(posedge clk) led_cnt <= led_cnt + 1;
//assign led = {led_cnt[23], led_cnt[22]};

endmodule