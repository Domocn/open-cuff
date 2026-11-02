from __future__ import annotations

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity, SensorStateClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.device_registry import CONNECTION_BLUETOOTH, DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.util import dt as dt_util

from . import SIGNAL_UPDATE, BP2Device
from .const import DOMAIN

SENSORS = [
    ("systolic", "Systolic", "mmHg", "mdi:heart-pulse", None),
    ("diastolic", "Diastolic", "mmHg", "mdi:heart-pulse", None),
    ("pulse", "Pulse", "bpm", "mdi:heart", None),
    ("time", "Last reading", None, "mdi:clock-outline", SensorDeviceClass.TIMESTAMP),
]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, add) -> None:
    dev: BP2Device = entry.runtime_data
    add([BP2Sensor(dev, *s) for s in SENSORS])


class BP2Sensor(SensorEntity):
    _attr_has_entity_name = True
    _unrecorded_attributes = frozenset({"readings"})
    _attr_should_poll = False

    def __init__(self, dev: BP2Device, key, name, unit, icon, device_class) -> None:
        self._dev = dev
        self._key = key
        self._attr_name = name
        self._attr_icon = icon
        self._attr_native_unit_of_measurement = unit
        self._attr_device_class = device_class
        if unit:
            self._attr_state_class = SensorStateClass.MEASUREMENT
        self._attr_unique_id = f"{dev.address}_{key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, dev.address)}, connections={(CONNECTION_BLUETOOTH, dev.address)},
            name=dev.entry.title, manufacturer="Viatom / OxiPro", model="BP2",
        )

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL_UPDATE.format(self._dev.entry.entry_id), self._update))

    @callback
    def _update(self) -> None:
        self.async_write_ha_state()

    @property
    def native_value(self):
        r = self._dev.latest
        if not r:
            return None
        if self._key == "time":
            return dt_util.parse_datetime(r["time"])
        return r.get(self._key)

    @property
    def extra_state_attributes(self):
        if self._key != "time":
            return None
        return {"last_sync": self._dev.last_sync, "last_error": self._dev.last_error,
                "irregular_pulse": (self._dev.latest or {}).get("irregular"), "readings": self._dev.recent}
