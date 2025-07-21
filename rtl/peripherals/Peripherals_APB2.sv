`timescale 1ns/1ps
`default_nettype none
/***********************************************************************************************************************
*                                                                                                                      *
* serial-console-server                                                                                                *
*                                                                                                                      *
* Copyright (c) 2025 Andrew D. Zonenberg and contributors                                                              *
* All rights reserved.                                                                                                 *
*                                                                                                                      *
* Redistribution and use in source and binary forms, with or without modification, are permitted provided that the     *
* following conditions are met:                                                                                        *
*                                                                                                                      *
*    * Redistributions of source code must retain the above copyright notice, this list of conditions, and the         *
*      following disclaimer.                                                                                           *
*                                                                                                                      *
*    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the       *
*      following disclaimer in the documentation and/or other materials provided with the distribution.                *
*                                                                                                                      *
*    * Neither the name of the author nor the names of any contributors may be used to endorse or promote products     *
*      derived from this software without specific prior written permission.                                           *
*                                                                                                                      *
* THIS SOFTWARE IS PROVIDED BY THE AUTHORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   *
* TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL *
* THE AUTHORS BE HELD LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES        *
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR       *
* BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT *
* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE       *
* POSSIBILITY OF SUCH DAMAGE.                                                                                          *
*                                                                                                                      *
***********************************************************************************************************************/

module Peripherals_APB2(

	//APB to root bridge
	APB.completer 			apb,
	APB.completer			apb64,

	//Clocks from top level PLL
	input wire				clk_125mhz,
	input wire				clk_250mhz,

	//RGMII PHY
	output wire				rgmii_tx_clk,
	output wire				rgmii_tx_en,
	output wire[3:0]		rgmii_txd,
	input wire				rgmii_rx_clk,
	input wire				rgmii_rx_dv,
	input wire[3:0]			rgmii_rxd,

	//Status outputs to GPIO core on APB1
	output wire				rgmii_link_up_core,
	output wire				rx_frame_ready
);

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// Pipeline register heading up to root bridge

	APB #(.DATA_WIDTH(32), .ADDR_WIDTH(16), .USER_WIDTH(0)) apb2_root();
	APBRegisterSlice #(.DOWN_REG(0), .UP_REG(0)) regslice_apb2_root(
		.upstream(apb),
		.downstream(apb2_root));

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// We only support 32-bit APB, throw synthesis error for anything else

	if(apb.DATA_WIDTH != 32)
		apb_bus_width_is_invalid();

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// APB bridge for peripherals on this bus

	//APB2
	localparam NUM_X32_PERIPHERALS	= 2;
	localparam BLOCK_SIZE		= 32'h1000;
	localparam ADDR_WIDTH		= $clog2(BLOCK_SIZE);
	APB #(.DATA_WIDTH(32), .ADDR_WIDTH(ADDR_WIDTH), .USER_WIDTH(0)) apb2[NUM_X32_PERIPHERALS-1:0]();
	APBBridge #(
		.BASE_ADDR(32'h0000_0000),
		.BLOCK_SIZE(BLOCK_SIZE),
		.NUM_PORTS(NUM_X32_PERIPHERALS)
	) bridge (
		.upstream(apb2_root),
		.downstream(apb2)
	);

	//APB64
	localparam NUM_X64_PERIPHERALS	= 2;
	APB #(.DATA_WIDTH(32), .ADDR_WIDTH(ADDR_WIDTH), .USER_WIDTH(0)) apb2_64[NUM_X64_PERIPHERALS-1:0]();
	APBBridge #(
		.BASE_ADDR(32'h0000_0000),
		.BLOCK_SIZE(BLOCK_SIZE),
		.NUM_PORTS(NUM_X64_PERIPHERALS)
	) bridge64 (
		.upstream(apb64),
		.downstream(apb2_64)
	);

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// Ethernet MAC

	AXIStream #(.DATA_WIDTH(32), .ID_WIDTH(0), .DEST_WIDTH(0), .USER_WIDTH(1)) mgmt0_axi_tx();
	AXIStream #(.DATA_WIDTH(32), .ID_WIDTH(0), .DEST_WIDTH(0), .USER_WIDTH(1)) mgmt0_axi_rx_phyclk();

	wire mgmt0_link_up_phyclk;
	wire mgmt0_link_up;

	AXIS_RGMIIMACWrapper #(
		.CLK_BUF_TYPE("LOCAL"),
		.PHY_INTERNAL_DELAY_RX(1)
	) port_mgmt0 (
		.clk_125mhz(clk_125mhz),
		.clk_250mhz(clk_250mhz),

		.rgmii_rxc(rgmii_rx_clk),
		.rgmii_rxd(rgmii_rxd),
		.rgmii_rx_ctl(rgmii_rx_dv),

		.rgmii_txc(rgmii_tx_clk),
		.rgmii_txd(rgmii_txd),
		.rgmii_tx_ctl(rgmii_tx_en),

		.axi_rx(mgmt0_axi_rx_phyclk),
		.axi_tx(mgmt0_axi_tx),

		.link_up(mgmt0_link_up_phyclk),
		.link_speed()
		);

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// Cross AXI RX buses for Ethernet into management clock domain

	AXIStream #(.DATA_WIDTH(32), .ID_WIDTH(0), .DEST_WIDTH(0), .USER_WIDTH(1)) mgmt0_axi_rx();
	AXIS_CDC #(
		.FIFO_DEPTH(1024)
	) mgmt0_rx_cdc (
		.axi_rx(mgmt0_axi_rx_phyclk),

		.tx_clk(apb64.pclk),
		.axi_tx(mgmt0_axi_rx)
	);

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// Shift link state flags into management clock domain

	(* keep_hierarchy = "yes" *)
	ThreeStageSynchronizer #(
		.IN_REG(1)
	) sync_mgmt0_link_up(
		.clk_in(mgmt0_axi_rx_phyclk.aclk),
		.din(mgmt0_link_up_phyclk),
		.clk_out(apb.pclk),
		.dout(mgmt0_link_up));

	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// FIFO for storing inbound/outbound Ethernet frames

	APB #(.DATA_WIDTH(32), .ADDR_WIDTH(ADDR_WIDTH), .USER_WIDTH(0)) mgmt0_apb_rx();
	APBRegisterSlice #(.DOWN_REG(0), .UP_REG(0)) regslice_apb_rx_fifo(
		.upstream(apb2[0]),
		.downstream(mgmt0_apb_rx));
	APB_AXIS_EthernetRxBuffer mgmt0_rx_fifo(
		.apb(mgmt0_apb_rx),
		.axi_rx(mgmt0_axi_rx),
		.eth_link_up(mgmt0_link_up),
		.rx_frame_ready(rx_frame_ready)
	);

	APB #(.DATA_WIDTH(32), .ADDR_WIDTH(ADDR_WIDTH), .USER_WIDTH(0)) mgmt0_apb_tx();
	APBRegisterSlice #(.DOWN_REG(1), .UP_REG(0)) regslice_apb_tx_fifo(
		.upstream(apb2_64[0]),
		.downstream(mgmt0_apb_tx));
	APB_AXIS_EthernetTxBuffer mgmt0_tx_fifo(
		.apb(mgmt0_apb_tx),

		.tx_clk(clk_125mhz),
		.link_up_pclk(mgmt0_link_up),
		.axi_tx(mgmt0_axi_tx)
	);

endmodule
