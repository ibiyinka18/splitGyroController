#include "fpga_link.h"
#include <zephyr/drivers/uart.h>
#include <zephyr/sys/ring_buffer.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(fpga_link, LOG_LEVEL_INF);

#define PACKET_LEN 21
#define SYNC0      0xAA
#define SYNC1      0x55

/* Two packets of slack. At 200 Hz the parser has 5 ms to drain a 21-byte
 * packet, so this only has to cover a scheduling hiccup, not a backlog.
 */
#define RX_RING_SIZE 64

static const struct device *uart_dev;

RING_BUF_DECLARE(rx_ring, RX_RING_SIZE);

static uint32_t bad_checksum;
static uint32_t dropped;
static uint32_t overruns;

/* ------------------------------------------------------------------ */
/* ISR: move bytes out of the uart fifo and into the ring, nothing else.
 * Parsing happens in thread context - an ISR should be short, and the
 * parser's state machine has no business running with interrupts masked.
 */
static void uart_isr(const struct device *dev, void *user_data)
{
	ARG_UNUSED(user_data);

	/* must be called once per isr before querying the irq state */
	uart_irq_update(dev);

	while (uart_irq_rx_ready(dev)) {
		uint8_t buf[32];
		int n = uart_fifo_read(dev, buf, sizeof(buf));

		if (n <= 0) {
			break;
		}

		/* If the ring is full the parser has fallen behind. Dropping
		 * here is correct: the checksum will reject whatever partial
		 * packet results, and the sync hunt resynchronises on the next
		 * one. Silently overwriting would corrupt a good packet instead.
		 */
		if (ring_buf_put(&rx_ring, buf, n) < (uint32_t)n) {
			overruns++;
		}
	}
}

int fpga_link_init(const struct device *uart)
{
	if (!device_is_ready(uart)) {
		LOG_ERR("uart device not ready");
		return -ENODEV;
	}

	uart_dev = uart;

	int err = uart_irq_callback_user_data_set(uart_dev, uart_isr, NULL);
	if (err) {
		LOG_ERR("could not set uart callback: %d", err);
		return err;
	}

	uart_irq_rx_enable(uart_dev);
	return 0;
}

/* ------------------------------------------------------------------ */
/* Thread side: hunt for the sync pattern, collect 21 bytes, validate. */

enum parse_state { WAIT_SYNC0, WAIT_SYNC1, COLLECT };

static enum parse_state state = WAIT_SYNC0;
static uint8_t  pkt[PACKET_LEN];
static size_t   idx;

static bool have_last_seq;
static uint8_t last_seq;

static int16_t be16(const uint8_t *p)
{
	return (int16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static bool checksum_ok(void)
{
	uint8_t sum = 0;

	/* xor over everything between the sync bytes and the checksum itself */
	for (size_t i = 2; i < PACKET_LEN - 1; i++) {
		sum ^= pkt[i];
	}

	return sum == pkt[PACKET_LEN - 1];
}

static void decode(struct sensor_packet *o)
{
	o->seq = pkt[2];

	const uint8_t st = pkt[3];
	o->calibrated = st & 0x01;
	o->is_still   = st & 0x02;
	o->cart_a     = (st >> 2) & 0x03;
	o->cart_b     = (st >> 4) & 0x03;

	o->accel_x = be16(&pkt[4]);
	o->accel_y = be16(&pkt[6]);
	o->accel_z = be16(&pkt[8]);
	o->gyro_x  = be16(&pkt[10]);
	o->gyro_y  = be16(&pkt[12]);
	o->gyro_z  = be16(&pkt[14]);
	o->pitch   = be16(&pkt[16]);
	o->roll    = be16(&pkt[18]);

	/* The sequence counter exists so gaps are visible rather than silently
	 * smoothing over missing samples.
	 */
	if (have_last_seq && (uint8_t)(o->seq - last_seq) != 1) {
		dropped++;
	}
	last_seq = o->seq;
	have_last_seq = true;
}

bool fpga_link_get(struct sensor_packet *out)
{
	uint8_t b;

	while (ring_buf_get(&rx_ring, &b, 1) == 1) {
		switch (state) {
		case WAIT_SYNC0:
			if (b == SYNC0) {
				state = WAIT_SYNC1;
			}
			break;

		case WAIT_SYNC1:
			if (b == SYNC1) {
				state = COLLECT;
				idx = 2;
			} else if (b != SYNC0) {
				/* a second 0xAA could still be the real first
				 * sync byte, so only a third value resets
				 */
				state = WAIT_SYNC0;
			}
			break;

		case COLLECT:
			pkt[idx++] = b;
			if (idx == PACKET_LEN) {
				state = WAIT_SYNC0;
				if (checksum_ok()) {
					decode(out);
					return true;
				}
				/* false sync on an 0xAA 0x55 inside the payload */
				bad_checksum++;
			}
			break;
		}
	}

	return false;
}

uint32_t fpga_link_bad_checksums(void) { return bad_checksum; }
uint32_t fpga_link_dropped(void)       { return dropped; }
uint32_t fpga_link_overruns(void)      { return overruns; }
