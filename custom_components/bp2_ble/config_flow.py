"""Config flow: the monitor is found automatically when it switches its Bluetooth on near a Home Assistant Bluetooth adapter or proxy."""
from __future__ import annotations

from typing import Any

import voluptuous as vol
from homeassistant.components.bluetooth import BluetoothServiceInfoBleak, async_discovered_service_info
from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_ADDRESS

from .const import DOMAIN, SERVICE_UUID


def _is_bp2(info: BluetoothServiceInfoBleak) -> bool:
    return "BP2" in (info.name or "").upper() or SERVICE_UUID in [u.lower() for u in info.service_uuids]


class BP2ConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._found: dict[str, str] = {}
        self._discovery: BluetoothServiceInfoBleak | None = None

    async def async_step_bluetooth(self, discovery_info: BluetoothServiceInfoBleak) -> ConfigFlowResult:
        await self.async_set_unique_id(discovery_info.address)
        self._abort_if_unique_id_configured()
        self._discovery = discovery_info
        self.context["title_placeholders"] = {"name": discovery_info.name or discovery_info.address}
        return await self.async_step_confirm()

    async def async_step_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        assert self._discovery is not None
        if user_input is not None:
            return self.async_create_entry(title=self._discovery.name or "BP2", data={CONF_ADDRESS: self._discovery.address})
        self._set_confirm_only()
        return self.async_show_form(step_id="confirm", description_placeholders={"name": self._discovery.name or self._discovery.address})

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            address = user_input[CONF_ADDRESS]
            await self.async_set_unique_id(address)
            self._abort_if_unique_id_configured()
            return self.async_create_entry(title=self._found.get(address, "BP2"), data={CONF_ADDRESS: address})
        current = self._async_current_ids()
        for info in async_discovered_service_info(self.hass, connectable=True):
            if info.address not in current and _is_bp2(info):
                self._found[info.address] = f"{info.name or 'BP2'} ({info.address})"
        if not self._found:
            return self.async_abort(reason="no_devices_found")
        return self.async_show_form(step_id="user", data_schema=vol.Schema({vol.Required(CONF_ADDRESS): vol.In(self._found)}))
