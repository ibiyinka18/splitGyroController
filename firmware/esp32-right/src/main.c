/* Right half - primary.
 *
 * For now this does one thing: receive the FPGA's sensor packets and print
 * them, which closes validation item 3 from the firmware side. Mapping,
 * profiles, ESP-NOW and USB HID come next.
 *
 * Scale factors come from the ICM-45686 datasheet for the ranges the FPGA
 * configures: gyro +/-2000 dps is 16.4 LSB per deg/s, accel +/-8g is 4096
 * LSB per g.
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/logging/log.h>
#include "fpga_link.h"

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

#define GYRO_LSB_PER_DPS 16.4f
#define ACCEL_LSB_PER_G  4096.0f

/* Named in the device tree overlay rather than hardcoded, so a different
 * board can put the link on a different uart without touching this file.
 */
static const struct device *const fpga_uart =
	DEVICE_DT_GET(DT_CHOSEN(fpga_link_uart));

static const char *cart_name(uint8_t id)
{
	switch (id) {
	case 0x3: return "none";
	case 0x2: return "stick";
	case 0x1: return "dpad";
	default:  return "spare";
	}
}

int main(void)
{
	struct sensor_packet pkt = {0};
	uint32_t packets = 0;

	if (fpga_link_init(fpga_uart) != 0) {
		LOG_ERR("fpga link failed to start");
		return 0;
	}

	LOG_INF("right half up, listening to the fpga at 1 Mbaud");

	int64_t next_report = k_uptime_get() + 1000;

	while (1) {
		if (fpga_link_get(&pkt)) {
			packets++;
		}

		/* Report once a second. Printing at 200 Hz would be unreadable
		 * and would itself become the bottleneck.
		 */
		if (k_uptime_get() >= next_report) {
			next_report += 1000;

			LOG_INF("%4u Hz | accel %+6.2f %+6.2f %+6.2f g | "
				"gyro %+8.1f %+8.1f %+8.1f dps | "
				"cart %s/%s | %s | bad %u drop %u ovr %u",
				packets,
				(double)(pkt.accel_x / ACCEL_LSB_PER_G),
				(double)(pkt.accel_y / ACCEL_LSB_PER_G),
				(double)(pkt.accel_z / ACCEL_LSB_PER_G),
				(double)(pkt.gyro_x / GYRO_LSB_PER_DPS),
				(double)(pkt.gyro_y / GYRO_LSB_PER_DPS),
				(double)(pkt.gyro_z / GYRO_LSB_PER_DPS),
				cart_name(pkt.cart_a), cart_name(pkt.cart_b),
				pkt.calibrated ? "calibrated" : "uncalibrated",
				fpga_link_bad_checksums(),
				fpga_link_dropped(),
				fpga_link_overruns());

			packets = 0;
		}

		/* Yield so logging and the idle thread get a look in. The ISR
		 * keeps filling the ring regardless of what this thread does.
		 */
		k_sleep(K_MSEC(1));
	}

	return 0;
}
