/* Receives the sensor packet the FPGA streams over uart.
 *
 * Packet, 21 bytes, as built by fpga/uart_tx_rx/sensor_packet.v:
 *
 *   0xAA 0x55 | seq | status | 12 sensor bytes | 4 angle bytes | xor
 *
 * Status byte:  [0] calibrated  [1] is_still  [3:2] cart_a  [5:4] cart_b
 * A receptacle id of 0b11 means nothing is inserted. The right half has one
 * receptacle, so cart_b always reads 0b11 there.
 *
 * Multi-byte fields are big endian. Note this is the opposite of how the
 * ICM-45686 returns them on the wire - the RTL already swaps them, so by the
 * time a packet reaches here everything is in the conventional order.
 *
 * A uart stream has no packet boundaries, so the receiver cannot simply read
 * 21 bytes at a time. Start mid-packet and every read after it is offset by
 * the same few bytes forever, producing values that look plausible and are
 * completely wrong. Hence the sync hunt, and the checksum before trusting
 * anything.
 */

#ifndef FPGA_LINK_H
#define FPGA_LINK_H

#include <zephyr/kernel.h>
#include <zephyr/device.h>

#define CART_NONE 0x3  /* 0b11 - nothing in the receptacle */

struct sensor_packet {
	uint8_t seq;
	bool    calibrated;	/* gyro bias has been learned */
	bool    is_still;	/* controller currently stationary */
	uint8_t cart_a;		/* receptacle ids, CART_NONE if empty */
	uint8_t cart_b;

	int16_t accel_x, accel_y, accel_z;
	int16_t gyro_x,  gyro_y,  gyro_z;
	int16_t pitch,   roll;	/* zero until the filter is on the FPGA */
};

/* Start receiving. The uart ISR fills a ring buffer; fpga_link_get drains it.
 * Returns 0 on success, negative errno otherwise.
 */
int fpga_link_init(const struct device *uart);

/* Non-blocking. Returns true and fills out when a whole, checksum-valid
 * packet is ready.
 */
bool fpga_link_get(struct sensor_packet *out);

/* Diagnostics. A rising bad-checksum count usually means a baud mismatch or
 * a noisy link; rising drops mean packets are being lost upstream.
 */
uint32_t fpga_link_bad_checksums(void);
uint32_t fpga_link_dropped(void);
uint32_t fpga_link_overruns(void);

#endif /* FPGA_LINK_H */
