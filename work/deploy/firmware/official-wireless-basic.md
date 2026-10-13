Title: [OpenWrt Wiki] Wi-Fi /etc/config/wireless

URL Source: https://openwrt.org/docs/guide-user/network/wifi/basic

Markdown Content:
The UCI wireless configuration is located in `/etc/config/wireless`. Note that if the device has Ethernet ports, wireless is turned **off** by default and using LuCI → Network → Wireless will also write to this file.

See also: [How do I enable Wi-Fi?](https://openwrt.org/faq/how_do_i_enable_wifi "faq:how_do_i_enable_wifi")

A typical wireless config file contains at least a pair of:

The _wifi-device_ refer to physical radio devices present on the system. The options present in this section describe properties common across all wireless interfaces on this radio device, such as channel or antenna selection.

A minimal _wifi-device_ declaration may look like the example below. Note that identifiers and options may vary for different chipset types or drivers.

config	wifi-device	'wl0'
	option	type	'broadcom'
	option	channel	'6'
The possible options for device sections are listed in the table below. Note that not all options are used for all chipset/driver types, refer to the comments for further details.

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _type_ | string | yes | _(autodetected)_ | The _type_ is determined on firstboot during the initial radio device detection - it is usually not required to change it. Used values are _broadcom_ on brcm47xx, or _mac80211_ for all other platforms |
| _phy_ | string | no/yes | _(autodetected)_ | Specifies the radio phy associated to this section. If present, it is usually autodetected and should not be changed. |
| _radio_ | string | no/yes | _(autodetected)_ | Specifies the radio associated with this section for chipsets with multi-band operation on a single physical wiphy. If present, it is usually autodetected and should not be changed. |
| _macaddr_ | MAC address | yes/no | _(autodetected)_ | Specifies the radio adapter associated to this section, it is _not_ used to change the device mac but to identify the underlying interface. |
| _disabled_ | boolean | no | _0_ | Disables the radio adapter if set to _1_. Removing this option or setting it to _0_ will enable the adapter |
| _channel_ | integer or “auto” | yes | _auto_ | Specifies the wireless channel. “auto” defaults to the lowest available channel, or [utilizes the ACS algorithm](https://forum.openwrt.org/t/wi-fi-channel-auto-selection/47776/8 "https://forum.openwrt.org/t/wi-fi-channel-auto-selection/47776/8") depending on hardware/driver support. |
| _channels_ | list | no | _(regulatory domain specific)_ | Use specific channels, when channel is in “auto” mode. This option allows hostapd to select one of the provided channels when a channel should be automatically selected. Channels can be provided as range using hyphen ('-') or individual channels can be specified by space (' ') separated values. |
| _hwmode_ | string | no | _(driver default)_ | Specifies the hardware mode, possible values are _11b_ for 2.4 GHz (used for legacy 802.11b only), _11g_ for 2.4 GHz (used for 802.11b, 802.11g and 802.11n) and _11a_ for 5 GHz (used for 802.11a, 802.11n and 802.11ac). Note that 11ng, 11na, 11n and 11ac are invalid options, this setting should largely be seen as controlling the frequency band. (**DEPRECATED** since 21.02.2, replaced with _band_) |
| _band_ | string | no | _(driver default)_ | Specifies the band, possible values are _2g_ for 2.4 GHz, _5g_ for 5 GHz, _6g_ for 6 GHz and _60g_ for 60 GHz. (**NEW** since 21.02.2, replaces _hwmode_) |
| _htmode_ | string | no | _(driver default)_ | Specifies the high throughput mode, used to control 802.11n (HT), 802.11ac (VHT) and 802.11ax (HE). The channel width used for these depends on this configuration. See [this section](https://openwrt.org/docs/guide-user/network/wifi/basic#htmodewi-fi_channel_width "docs:guide-user:network:wifi:basic") for details. Possible values are: _HT20_, _HT40-_, _HT40+_, _HT40_, or _VHT20_, _VHT40_, _VHT80_, _VHT160_, _NOHT_ disables 11n and 11ac, HE20, HE40, HE80, HE160 |
| _chanbw_ | integer | no | 20 | Specifies a narrow channel width in MHz, possible values are: _5_, _10_, _20_ |
| _ht\_capab_ | string | no | _(driver default)_ | Specifies the available capabilities of the radio. The values are autodetected. See [here](http://w1.fi/cgit/hostap/tree/hostapd/hostapd.conf "http://w1.fi/cgit/hostap/tree/hostapd/hostapd.conf") for options (check vs. the version of hostapd installed on your router using the “refs” link) |
| _txpower_ | integer | no | _(driver default)_ | Specifies the maximum desired _transmission power in dBm_. The actual txpower used depends on regulatory requirements. |
| _diversity_ | boolean | no | _1_ | Enables or disables the automatic antenna selection by the driver |
| _rxantenna_ | integer | no | _(driver default)_ | Specifies the _antenna for receiving_, the value may be driver specific, usually it is _1_ for the first and _2_ for the second antenna. Specifying _0_ enables automatic selection by the driver if supported. This option has no effect if diversity is enabled |
| _txantenna_ | integer | no | _(driver default)_ | Specifies the _antenna for transmitting_, values are identical to _rxantenna_ |
| _country_ | varies | no | _(driver default)_ | Specifies the country code, affects the available channels and transmission powers. For types _mac80211_ and _broadcom_ a two letter ISO country code is used (e.g. _JP_ or _DE_). The _madwifi_ driver expects a numeric code. |
| _country\_ie_ | boolean | no | 1 if _country_ is set, otherwise 0 | Enables IEEE 802.11d country IE (information element) advertisement in beacon and probe response frames. This IE contains the country code and channel/power map. Requires _country_. |
| _distance_ | string | no | _(driver default)_ | Distance between the ap and the furthest client in meters. |
| _beacon\_int_ | integer | no | _100 (hostapd default)_ | Set the beacon interval. This is the time interval between beacon frames, measured in units of 1.024 ms. hostapd permits this to be set between 15 and 65535. This option has no effect on _sta_ type wifi-ifaces |
| _legacy\_rates_ | boolean | no | _1 in 19.07, 0 in 21.02_ | 0 = Disallow legacy 802.11b data rates, 1 = Allow legacy 802.11b data rates. Legacy or badly behaving devices may require legacy 802.11b rates to interoperate. Airtime efficiency may be significantly reduced where these are used. It is recommended to not allow 802.11b rates where possible. The basic_rate and supported_rates options overrides this option. |
| _require\_mode_ | string | no | _none_ | Sets the minimum client capability level mode that connecting clients must support to be allowed to connect. Overrides and sets legacy_rates to 0 to disable legacy 802.11b data rates. Supported values: n = 802.11n, ac = 802.11ac ![Image 1: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Warning: setting this value to “ac” causes reliability problems from Apple devices, even if they actually support 802.11ac or better. |
| _cell\_density_ | integer | no | _0, supported in 21.02_ | Configures data rates based on the coverage cell density. Normal configures basic rates to 6, 12, 24 Mbps if legacy_rates is 0, else to 5.5, 11 Mbps. High configures basic rates to 12, 24 Mbps if legacy_rates is 0, else to the 11 Mbps rate. Very High configures 24 Mbps as the basic rate. Supported rates lower than the minimum basic rate are not offered. The basic_rate and supported_rates options overrides this option. 0 = Disabled, 1 = Normal, 2 = High, 3 = Very High |
| _basic\_rate_ | list | no | _(hostapd/driver default)_ | Set the basic data rates. Each basic_rate is measured in kb/s. This option only has an effect on _ap_ and _adhoc_ wifi-ifaces. It is recommended to use the cell_density option instead. |
| _supported\_rates_ | list | no | _(hostapd/driver default)_ | Set the supported data rates. Each supported rate is measured in kb/s. This option only has an effect on _ap_ and _adhoc_ wifi-ifaces. This must be a superset of the rates set in basic_rate. The minimum basic rate should also be the minimum supported rate. It is recommended to use the cell_density option instead. |
| _log\_level_ | integer | no | 2 | Set the log_level. Supported levels are: 0 = Verbose Debugging, 1 = Debugging, 2 = Informational Messages, 3 = Notification, 4 = Warning |
| _hostapd\_options_ | list | no | _none_ | Pass any custom options to `hostapd-*.conf`. Values passed _as-is_. For example, used when setting vendor-specific informational element to [make Windows clients detect Wi-Fi as metered connection](https://openwrt.org/docs/guide-user/network/wifi/ms-meteredconnection "docs:guide-user:network:wifi:ms-meteredconnection") |

The options below are specific to the mac80211 framework which is used by the majority of hardware supported by OpenWrt.

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _path_ | string | no | _(none)_ | Alternative to phy used to identify the device based paths in /sys/devices |
| _htmode_ | string | no | _(driver default)_ | Specifies the channel width in 802.11n and 802.11ac mode, possible values are: HT20 (single 20MHz channel), HT40- (2x 20MHz channels, primary/control channel is upper, secondary channel is below), HT40+ (2x 20MHz channels, primary/control channel is lower, secondary channel is above), HT40 (2x 20Mz channels, auto selection of upper or lower secondary channel on versions 14.07 and above), NONE (disables 802.11n rates and enforce the usage of legacy 802.11 b/g/a rates) VHT20 / VHT40 / VHT80 / VHT160 (channel width in 802.11ac, extra channels are picked according to the specification) HE20 / HE40 / HE80 / HE160 (channel width in 802.11ax) See also: [Why can't I use HT40+ with channel 11?](https://forum.archive.openwrt.org/viewtopic.php?id=22742&p=48#p156165 "https://forum.archive.openwrt.org/viewtopic.php?id=22742&p=48#p156165") ![Image 2: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) See HT (high throughput) capabilities below for options to customize high-throughput modes |
| _chanbw_ | integer | no | 20 | Specifies a narrow channel width, possible values are: 5 (5MHz channel), 10 (10MHz channel) or 20 (20MHz channel). ![Image 3: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Only supported by the ath9k/ath5k driver |
| _noscan_ | boolean | no | 0 | Do not scan for overlapping BSSs in HT40+/- or HE40 modes in the 2.4GHz band. This scan is a polite behaviour when the band is congested, falling back to 20 MHz if overlap is detected. It is not a regulatory mandate. |
| _beacon\_int_ | integer | no | 100 _(hostapd default)_ | Set the beacon interval. This is the time interval between beacon frames, measured in units of 1.024 ms. hostapd permits this to be set between 15 and 65535. This option has no effect on _sta_ type wifi-ifaces. |
| _basic\_rate_ | list | no | _(hostapd/driver default)_ | Set the supported basic rates. Each basic_rate is measured in kb/s. This option only has an effect on ap and adhoc wifi-ifaces. |
| _supported\_rates_ | list | no | _(hostapd/driver default)_ | Set the supported rates. Each supported_rates is measured in kb/s. This option only has an effect on ap wifi-ifaces. |
| _ht\_coex_ | integer | no | 0 | Disable honoring 40 MHz intolerance in coexistence flags of stations. When enabled, the radio will _not_ stop using the 40 MHz channels if the 40 MHz intolerance indication is received from another AP or station. |
| _frag_ | integer | no | _(none)_ | Fragmentation threshold |
| _rts_ | integer | no | _(driver default)_ | Override the RTS/CTS threshold |
| _antenna\_gain_ | integer | no | 0 | Reduction in antenna gain from regulatory maximum in dBi |

![Image 4: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) The options below are only used by the proprietary Broadcom driver (type _broadcom_).

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _frameburst_ | boolean | no | _0_ | Enables Broadcom frame bursting (Xpress Technology) if supported |
| _maxassoc_ | integer | no | _(driver default)_ | Limits the maximum allowed number of associated clients |
| _slottime_ | integer | no | _(driver default)_ | Slot time in milliseconds |

![Image 5: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) The options below are only used by the Ubiquiti Nanostation family of devices.

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _antenna_ | string | no | _(driver default)_ | Specifies the antenna, possible values are _vertical_ for internal vertical polarization, _horizontal_ for internal horizontal polarization or _external_ to use the external antenna connector |

A complete wireless configuration contains at least one _wifi-iface_ section per adapter to define a wireless network on top of the hardware. Some drivers support multiple wireless networks per device:

A minimal example for a _wifi-iface_ declaration is given below.

config	wifi-iface
	option	device		'wl0'
	option	network		'lan'
	option	mode		'ap'
	option	ssid		'MyWifiAP'
	option	encryption	'psk2'
	option	key		'secret passphrase'

The common configuration options for _wifi-iface_ sections are listed below.

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _ifname_ | string | no | _(driver default)_ | Specifies a custom name for the Wi-Fi interface, which is otherwise automatically named. Maximum length: 15 characters. Note that [DSA support](https://openwrt.org/docs/guide-user/network/dsa/start "docs:guide-user:network:dsa:start") does not affect wireless configuration, so this option is still valid. |
| _device_ | string or string array | yes | _(first device id)_ | Specifies the used wireless adapter, must refer to one or more of the defined _wifi-device_ sections. |
| _network_ | string array | yes | _lan_ | Specifies one or multiple logical network interfaces declared in the network configuration, each one should be a L3 bridge to be able to attach this L2 wireless interface. |
| _mode_ | string | yes | _ap_ | Specifies the operation mode of the wireless network interface controller. Possible values are _ap_, _sta_, _adhoc_, _monitor_, _mesh_. NB: for wds mode, use `option wds 1` with either `option mode 'ap`' or `option mode 'sta`'. |
| _disabled_ | boolean | no | _0_ | When set to 1, wireless network is disabled. |
| _ssid_ | string | yes | OpenWrt | The broadcasted SSID of the wireless network and for for managed mode the SSID of the network you’re connecting to. |
| _bssid_ | BSSID address | no | _(driver default)_ | Override the BSSID of the network, only applicable in _adhoc_ or _sta_ mode. In _wds_ mode specifies the BSSID of another AP to create WDS with. |
| _mesh\_id_ | Mesh ID | no | none | The Mesh ID as defined in IEEE 802.11s. If set, the wireless interface will join this mesh network when brought up. If not, it is necessary to invoke _iw <iface> mesh join <mesh\_id>_ to join a mesh after the interface is brought up. |
| _hidden_ | boolean | no | _0_ | Disables the broadcasting of beacon frames if set to _1_ and, in doing so, hides the ESSID. Where the ESSID is hidden, clients may fail to roam and airtime efficiency may be significantly reduced. |
| _isolate_ | boolean | no | _0_ | Isolates wireless clients from each other, only applicable in _ap_ mode. See [this](https://forum.openwrt.org/t/clients-in-same-wlan-cant-reach-each-other/2501/22 "https://forum.openwrt.org/t/clients-in-same-wlan-cant-reach-each-other/2501/22") post for details. |
| _bridge\_isolate_ | boolean | no | _0_ | Isolates wireless clients from each other on the AP's bridge. (i.e. 2.4ghz and 5ghz radios on the same AP.) |
| _doth_ | boolean | no | _0_ | Enables 802.11h support. |
| _wmm_ | boolean | no | _1_ | Enables WMM. Where Wi-Fi Multimedia (WMM) Mode QoS is disabled, clients may be limited to 802.11a/802.11g rates. Required for 802.11n/802.11ac/802.11ax. |
| _encryption_ | string | no | _none_ | Wireless encryption method. Possible values are listed in the [encryption values](https://openwrt.org/docs/guide-user/network/wifi/basic#encryption_modes "docs:guide-user:network:wifi:basic") table, right after this table. |
| _key_ | integer or string | no | _(none)_ | In any **WPA-PSK** mode, this is a string that specifies the pre-shared passphrase from which the pre-shared key will be derived. The clear text key has to be 8-63 characters long. If a 64-character hexadecimal string is supplied, it will be used directly as the pre-shared key instead. In **WEP** mode, this can be an integer specifying which key index to use (_key1_, _key2_, _key3_, or _key4_.) Alternatively, it can be a string specifying a passphrase or key directly, as in _key1_. In any **WPA-Enterprise AP** mode, this option has a different interpretation. |
| _key1_ | string | no | _(none)_ | WEP passphrase or key #1 (selected by the index in _key_). This string is treated as a passphrase from which the WEP key will be derived. If a 10- or 26-character hexadecimal string is supplied, it will be used directly as the WEP key instead. |
| _key2_ | string | no | _(none)_ | WEP passphrase or key #2 (selected by the index in _key_), as in _key1_. |
| _key3_ | string | no | _(none)_ | WEP passphrase or key #3 (selected by the index in _key_), as in _key1_. |
| _key4_ | string | no | _(none)_ | WEP passphrase or key #4 (selected by the index in _key_), as in _key1_. |
| _macfilter_ | string | no | _disable_ | Specifies the _mac filter policy_, _disable_ to disable the filter, _allow_ to treat it as whitelist or _deny_ to treat it as blacklist. |
| _maclist_ | list of MAC addresses | no | _(none)_ | List of MAC addresses (divided by spaces) to put into the mac filter. |
| _iapp\_interface_ | string | no | _(none)_ | Specifies a network interface to be used for 802.11f (IAPP) - only enabled when defined. |
| _rsn\_preauth_ | boolean | no | _0_ | Allow preauthentication for WPA2-EAP networks (and advertise it in WLAN beacons). Only works if the specified network interface is a bridge. |
| _ieee80211w_ | integer | no | _0_ | Enables MFP (802.11w) support (0 = disabled, 1 = optional, 2 = required). |
| _ieee80211w\_max\_timeout_ | integer | no | _(hostapd default)_ | Specifies the 802.11w Association SA Query maximum timeout. |
| _ieee80211w\_retry\_timeout_ | integer | no | _(hostapd default)_ | Specifies the 802.11w Association SA Query retry timeout. |
| _sae\_require\_mfp_ | boolean | no | 1 | Require MFP for all associations using SAE. Useful for when 802.11w is set to optional for WPA2/WPA3 mixed mode. |
| _maxassoc_ | integer | no | _(hostapd/driver default)_ | Specifies the maximum number of clients to connect. |
| _macaddr_ | MAC address or string | no | _(hostapd/driver default)_ | Overrides the MAC address used for the Wi-Fi interface. Warning: if the MAC address specified is a multicast address, this override will fail silently. To avoid this problem, ensure that the MAC address specified is a valid unicast MAC address. When set to `random`, a new locally administered unicast MAC address is generated and assigned to the iface everytime it is (re-)configured. |
| _dtim\_period_ | integer | no | _2 (hostapd default)_ | Set the DTIM (delivery traffic information message) period. There will be one DTIM per this many beacon frames. This may be set between 1 and 255. This option has no effect on _sta_ type wifi-ifaces. ![Image 6: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Some users report that this needs to be set to 3 to avoid reliability problems with Apple devices. |
| _short\_preamble_ | boolean | no | _1_ | Set optional use of short preamble |
| _max\_listen\_int_ | integer | no | _65535 (hostapd default)_ | Set the maximum allowed STA (client) listen interval. Association will be refused if a STA attempts to associate with a listen interval greater than this value. This option only has an effect on _ap_ wifi-ifaces. |
| _mcast\_rate_ | integer | no | _(driver default)_ | Sets the fixed multicast rate, measured in kb/s. **Only supported in adhoc and mesh modes** |
| _wds_ | boolean | no | _0_ | This sets [4-address mode](https://wireless.wiki.kernel.org/en/users/documentation/iw#using_4-address_for_ap_and_client_mode "https://wireless.wiki.kernel.org/en/users/documentation/iw#using_4-address_for_ap_and_client_mode") |
| _owe\_transition\_ssid_ | string | no | _none_ | Opportunistic Wireless Encryption (OWE) Transition SSID (only for OPEN and OWE networks) |
| _owe\_transition\_bssid_ | BSSID address | no | _none_ | Opportunistic Wireless Encryption (OWE) Transition BSSID (only for OPEN and OWE networks) |
| _sae\_pwe_ | integer | no | _0 (hostapd default)_ | Sets the SAE mechanism for PWE derivation (0 = hunting-and-pecking only, 1 = hash-to-element only, 2 = both hunting-and-pecking and hash-to-element) |
| _ocv_ | integer | no | _0 (hostapd/wpa\_supplicant default)_ | Configuration option for Operating Channel Validation. When operating as an access point the following options are available: 0 = disabled, 1 = enabled, 2 = enabled in workaround mode - Allow STA that claims OCV capability to connect even if the STA doesn't send OCI or negotiate PMF. When operating in client mode the following options are available: 0 = disabled, 1 = enabled if wpa_supplicant's SME in use. Otherwise enabled only when the driver indicates support for operating channel validation. |
| _mlo_ | boolean | no | _0_ | Enable MLO (Multi-Link Operation) |
| _start\_disabled_ | boolean | no | _0_ | For an AP, start with beaconing disabled by default (see _start\_disabled_ in hostapd.conf). Note that if an interface with mode _sta_ is also defined on the same radio, _start\_disabled_ will be added in the hostapd configuration, regardless of the value set for the AP. |
| _default\_disabled_ | boolean | no | _0_ | For an STA, add _disabled_ to the default wpa_supplicant network block (to prevent it from scanning by default). The network block can still be enabled, for example by using _wpa\_cli_ (see _disabled_ in wpa_supplicant.conf). |
| _hostapd\_bss\_options_ | list | no | _none_ | Pass any custom options to `hostapd-*.conf`. Values passed _as-is_. |

Besides the encryption mode, the _encryption_ option also specifies the group and peer ciphers to use. To override the cipher, the value of _encryption_ must be given in the form _mode+cipher_. See the listing below for possible combinations.

WPA3 modes are supported by default starting with the [OpenWrt 21.02](https://openwrt.org/releases/21.02/notes-21.02.0#wpa3_support_included_by_default "releases:21.02:notes-21.02.0") release.

| Value | Type | Ciphers | Supported since |
| --- | --- | --- | --- |
| _none_ | no authentication | none |  |
| _sae_ | WPA3 Personal (SAE) | CCMP | 19.07 |
| _sae-mixed_ | WPA2/WPA3 Personal (PSK/SAE) mixed mode | CCMP | 19.07 |
| _psk2+tkip+ccmp_ | WPA2 Personal (PSK) | TKIP, CCMP |  |
| _psk2+tkip+aes_ | WPA2 Personal (PSK) | TKIP, CCMP |  |
| _psk2+tkip_ | WPA2 Personal (PSK) | TKIP |  |
| _psk2+ccmp_ | WPA2 Personal (PSK) | CCMP |  |
| _psk2+aes_ | WPA2 Personal (PSK) | CCMP |  |
| _psk2_ | WPA2 Personal (PSK) | CCMP |  |
| _psk+tkip+ccmp_ | WPA Personal (PSK) | TKIP, CCMP |  |
| _psk+tkip+aes_ | WPA Personal (PSK) | TKIP, CCMP |  |
| _psk+tkip_ | WPA Personal (PSK) | TKIP |  |
| _psk+ccmp_ | WPA Personal (PSK) | CCMP |  |
| _psk+aes_ | WPA Personal (PSK) | CCMP |  |
| _psk_ | WPA Personal (PSK) | CCMP |  |
| _psk-mixed+tkip+ccmp_ | WPA/WPA2 Personal (PSK) mixed mode | TKIP, CCMP |  |
| _psk-mixed+tkip+aes_ | WPA/WPA2 Personal (PSK) mixed mode | TKIP, CCMP |  |
| _psk-mixed+tkip_ | WPA/WPA2 Personal (PSK) mixed mode | TKIP |  |
| _psk-mixed+ccmp_ | WPA/WPA2 Personal (PSK) mixed mode | CCMP |  |
| _psk-mixed+aes_ | WPA/WPA2 Personal (PSK) mixed mode | CCMP |  |
| _psk-mixed_ | WPA/WPA2 Personal (PSK) mixed mode | CCMP |  |
| _wep_ | defaults to “open system” authentication aka **wep+open** | RC4 |  |
| _wep+open_ | “open system” authentication | RC4 |  |
| _wep+shared_ | “shared key” authentication | RC4 |  |
| _wpa3_ | WPA3 Enterprise | CCMP | 19.07 |
| _wpa3-mixed_ | WPA3/WPA2 Enterprise | CCMP | 19.07 |
| _wpa2+tkip+ccmp_ | WPA2 Enterprise | TKIP, CCMP |  |
| _wpa2+tkip+aes_ | WPA2 Enterprise | TKIP, CCMP |  |
| _wpa2+ccmp_ | WPA2 Enterprise | CCMP |  |
| _wpa2+aes_' | WPA2 Enterprise | CCMP |  |
| _wpa2_ | WPA2 Enterprise | CCMP |  |
| _wpa2+tkip_ | WPA2 Enterprise | TKIP |  |
| _wpa+tkip+ccmp_ | WPA Enterprise | TKIP, CCMP |  |
| _wpa+tkip+aes_ | WPA Enterprise | TKIP, AES |  |
| _wpa+ccmp_ | WPA Enterprise | CCMP |  |
| _wpa+aes_ | WPA Enterprise | CCMP |  |
| _wpa+tkip_ | WPA Enterprise | TKIP |  |
| _wpa_ | WPA Enterprise | CCMP |  |
| _wpa-mixed+tkip+ccmp_ | WPA/WPA2 Enterprise mixed mode | TKIP, CCMP |  |
| _wpa-mixed+tkip+aes_ | WPA/WPA2 Enterprise mixed mode | TKIP, CCMP |  |
| _wpa-mixed+tkip_ | WPA/WPA2 Enterprise mixed mode | TKIP |  |
| _wpa-mixed+ccmp_ | WPA/WPA2 Enterprise mixed mode | CCMP |  |
| _wpa-mixed+aes_ | WPA/WPA2 Enterprise mixed mode | CCMP |  |
| _wpa-mixed_ | WPA/WPA2 Enterprise mixed mode | CCMP |  |
| _owe_ | Opportunistic Wireless Encryption (OWE) | CCMP | 19.07 |

Listing of Access Point options for WPA Enterprise.

| Name | Default | Description |
| --- | --- | --- |
| _server_ | _(none)_ | RADIUS server to handle client authentication |
| _port_ | _1812_ | RADIUS port |
| _key_ | _(none)_ | Shared RADIUS secret |
| _wpa\_group\_rekey_ | _600_ | WPA Group Cipher rekeying interval in seconds |
| _auth\_server_ | _(none)_ | RADIUS authentication server to handle client authentication |
| _auth\_port_ | _1812_ | RADIUS authentication port |
| _auth\_secret_ | _(none)_ | Shared authentication RADIUS secret |
| _auth\_cache_ | _0_ | Disable or enable PMKSA and Opportunistic Key Caching |
| _acct\_server_ | _(none)_ | RADIUS accounting server to handle client authentication |
| _acct\_port_ | _1813_ | RADIUS accounting port |
| _acct\_secret_ | _(none)_ | Shared accounting RADIUS secret |
| _nasid_ | _(none)_ | NAS ID for RADIUS authentication requests |
| _ownip_ | _(none)_ | NAS IP Address for RADIUS authentication requests |
| _dae\_client_ | _(none)_ | Dynamic Authorization Extension client. This client can send “Disconnect-Request” or “CoA-Request” packets to forcibly disconnect a client or change connection parameters. |
| _dae\_port_ | _3799_ | Port the Dynamic Authorization Extension server listens on. |
| _dae\_secret_ | _(none)_ | Shared DAE secret. |
| _dynamic\_vlan_ | _0_ | Dynamic VLAN assignment |
| _vlan\_naming_ | _1_ | VLAN Naming |
| _vlan\_tagged\_interface_ | _(none)_ | VLAN Tagged Interface |
| _vlan\_bridge_ | _(none)_ | VLAN Bridge Naming Scheme - added in [hostapd: improve 802.1x dynamic vlan support with bridge names](https://git.openwrt.org/?p=openwrt/openwrt.git;a=commitdiff;h=d40842d1801e65156d27d727d4fba4735728a844 "https://git.openwrt.org/?p=openwrt/openwrt.git;a=commitdiff;h=d40842d1801e65156d27d727d4fba4735728a844") |
| _radius\_client\_addr_ | _(none)_ | Source-IP for RADIUS requests. |

Listing of Client related options for WPA Enterprise.

| Name | Default | Description |
| --- | --- | --- |
| _eap\_type_ | _(none)_ | Defines the EAP protocol, possible values are _tls_ for EAP-TLS and _peap_ or _ttls_ for EAP-PEAP |
| _auth_ | _MSCHAPV2_ | “auth=PAP”/PAP/MSCHAPV2 - Defines the phase 2 (inner) authentication method, only applicable if _eap\_type_ is _peap_ or _ttls_ |
| _identity_ | _(none)_ | EAP identity to send during authentication |
| _password_ | _(none)_ | Password to send during EAP authentication |
| _ca\_cert_ | _(none)_ | Specifies the path the CA certificate used for authentication |
| _client\_cert_ | _(none)_ | Specifies the client certificate used for the authentication |
| _priv\_key_ | _(none)_ | Specifies the path to the private key file used for authentication, only applicable if _eap\_type_ is set to _tls_ |
| _priv\_key\_pwd_ | _(none)_ | Password to unlock the private key file, only works in conjunction with _priv\_key_ |

![Image 7: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) When using WPA Enterprise type PEAP with Active Directory Servers, the “auth” option must be set to “auth=MSCHAPV2” or “auth=PAP”.

option auth 'auth=MSCHAPV2'
or

option auth 'auth=PAP'

The wpa_psk_file option specifies an external file containing a list of MAC address and PSK/passphrase pairs, allowing for multiple PSK/passphrases.

| Name | Default | Description |
| --- | --- | --- |
| _wpa\_psk\_file_ | (none) | Location of the wpa_psk file (a common location is /etc/hostapd.wpa_psk) |

Example for a wpa_psk file:

00:00:00:00:00:00 secret_passphrase
00:00:00:00:00:00 another_passphrase
00:11:22:33:44:55 passphrase_for_a_specific_mac_only
00:22:33:44:55:66 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
vlanid=3 00:00:00:00:00:00 passphrase_for_vlan_id_3
In the example above, the last line uses the “vlanid=<id>” parameter: Clients can be assigned to VLAN-tagged interfaces depending on the PSK/passphrase. Additional configuration is required, re-using several parameters originally intended for RADIUS-based VLAN mappings:

| Name | Default | Description |
| --- | --- | --- |
| _dynamic\_vlan_ | _0_ | Dynamic VLAN mode: 0 = disabled, 1 = optional (use default interface when no VLAN ID is used), 2 = required |
| _vlan\_file_ | (none) | Absolute path to the file containing VLAN ID - network interface mappings (a common location is /etc/hostapd.vlan) |
| _vlan\_tagged\_interface_ | _(none)_ | prefix for the vlan tagged interface (see vlan_naming option) |
| _vlan\_naming_ | _1_ | VLAN naming scheme prefix for the newly created interface: 0 = “vlan<id>”, 1 = “<vlan_tagged_interface>.<id>” (see vlan_tagged_interface option) |
| _vlan\_bridge_ | _(none)_ | bridge prefix for the bridge to which the wifi and the tagged interface will be added; defaults to “brvlan<id>” if no tagged interface is given and “br<vlan_tagged_interface>.<id>” if a tagged interface is given (see vlan_tagged_interface option) |

Note: The vlan-related options above will be ignored or rejected by the default stripped down wpad-basic/hostapd-basic binaries. Like a RADIUS-based setup, these require the fully featured wpad/hostapd.

Example for a vlan file:

# VLAN ID to network interface mapping
1	vlan1
2	vlan2
3	vlan3
100	guest
# Optional wildcard entry matching all VLAN IDs. The first "#" in the interface name will be replaced with the VLAN ID.
# The network interfaces are created and removed dynamically when necessary.
*	vlan#
# Optional third parameter to override the bridge name
101	vlan100	bridge_name

| Name | Default | Description |
| --- | --- | --- |
| _wpa\_disable\_eapol\_key\_retries_ | _0_ | Workaround for key reinstallation attacks (requires LEDE 17.01.4 or higher) |

Complete description copied from upstream hostapd.conf example:

# Workaround for key reinstallation attacks
#
# This parameter can be used to disable retransmission of EAPOL-Key frames that
# are used to install keys (EAPOL-Key message 3/4 and group message 1/2). This
# is similar to setting wpa_group_update_count=1 and
# wpa_pairwise_update_count=1, but with no impact to message 1/4 and with
# extended timeout on the response to avoid causing issues with stations that
# may use aggressive power saving have very long time in replying to the
# EAPOL-Key messages.
#
# This option can be used to work around key reinstallation attacks on the
# station (supplicant) side in cases those station devices cannot be updated
# for some reason. By removing the retransmissions the attacker cannot cause
# key reinstallation with a delayed frame transmission. This is related to the
# station side vulnerabilities CVE-2017-13077, CVE-2017-13078, CVE-2017-13079,
# CVE-2017-13080, and CVE-2017-13081.
#
# This workaround might cause interoperability issues and reduced robustness of
# key negotiation especially in environments with heavy traffic load due to the
# number of attempts to perform the key exchange is reduced significantly. As
# such, this workaround is disabled by default (unless overridden in build
# configuration). To enable this, set the parameter to 1.
#wpa_disable_eapol_key_retries=1
**Note** that this workaround can't prevent attacks against Tunneled Direct-Link Setup (TDLS). You may also want to add the option _tdls\_prohibit=1_ in order to make such an attack more complicated:

| Name | Default | Description |
| --- | --- | --- |
| _tdls\_prohibit_ | _0_ | Prohibit the use of TDLS on the network (complicates key reinstallation attacks against TDLS) (requires hostapd/wpad 2016-12-19-ad02e79d-7 or higher) |

Listing of [Wi-Fi Protected Setup](http://en.wikipedia.org/wiki/Wi-Fi_Protected_Setup "http://en.wikipedia.org/wiki/Wi-Fi_Protected_Setup") related options.

![Image 8: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Support for WPS is provided by packages _wpad_ and _hostapd-utils_. Default package _wpad-mini_ is not enough.

![Image 9: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) WPS is possible only when encryption PSK/PSK2 is selected.

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _wps\_config_ | list | no | _(none)_ | List of configuration methods. Currentlly supported methods are: _push\_button_. |
| _wps\_device\_name_ | string | no | _LEDE AP_ | User-friendly description of device; up to 32 octets encoded in UTF-8. |
| _wps\_device\_type_ | string | no | _6-0050F204-1_ | Primary device type. Examples: _1-0050F204-1_ (Computer / PC), _1-0050F204-2_ (Computer / Server), _5-0050F204-1_ (Storage / NAS), _6-0050F204-1_ (Network Infrastructure / AP) |
| _wps\_label_ | boolean | no | _0_ | Enable _label_ configuration method. |
| _wps\_manufacturer_ | string | no | _lede-project.org_ | The manufacturer of the device (up to 64 ASCII characters). |
| _wps\_pushbutton_ | boolean | no | _0_ | Enable _push-button_ configuration method. |
| _wps\_pin_ | string | no | none | The PIN to use with WPS-PIN (only in external registrar mode?) |

Minimal steps needed to get WPS running:

After rebooting, instead of pushing the WPS button, you can manually initiate the WPS process (which is safer than using the button if it doubles as a reset button):

hostapd_cli wps_pbc
When using WPS-PIN:

After rebooting, the WPS PIN needs to be given to hostapd each time a station tries to connect. The PIN may **not** be used multiple times, as an active attacker can recover half of it during each try. The “any” keyword can be replaced by the specific stations EUUID, as printed in hostapd log.

hostapd_cli wps_pin any $PIN
Example:

# /etc/config/wireless
...
config wifi-iface
	option device 'radio0'
	option mode 'ap'
	option ssid 'My-WiFi-Home'
	option network 'lan'
	option encryption 'psk2'
	option key 'WiFipassword'
	option ieee80211w '0'
	option wps_pushbutton '1'

To enable neighbor ports, you must install the “full” version of hostapd or wpad **and** install and configure additional software to distribute neighbor reports between access points (including dual band access points on the same physical device). See also [Wifi Roaming](https://openwrt.org/docs/guide-user/network/wifi/roaming "docs:guide-user:network:wifi:roaming").

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _ieee80211k_ | boolean | no | _0_ | Enables Radio Resource Measurement (802.11k) support. |
| _rrm\_neighbor\_report_ | boolean | no | Value of _ieee80211k_ | Enable neighbor report via radio measurements. |
| _rrm\_beacon\_report_ | boolean | no | Value of _ieee80211k_ | Enable beacon report via radio measurements. |

This function needs the full version of hostapd or wpad. See also [Wifi Roaming](https://openwrt.org/docs/guide-user/network/wifi/roaming "docs:guide-user:network:wifi:roaming").

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _ieee80211v (Removed)_ | boolean | no | _0_ | Enables BSS transition (802.11v) support. This option was removed in [this](https://github.com/openwrt/openwrt/commit/b518f07d4b8ae144453c606c9ec4ecef7d39f968 "https://github.com/openwrt/openwrt/commit/b518f07d4b8ae144453c606c9ec4ecef7d39f968") commit. |
| _time\_advertisement_ | integer | no | _0_ | Time advertisement. 0 is disabled and 2 is enabled (see hostapd's [time_advertisement](https://w1.fi/cgit/hostap/plain/hostapd/hostapd.conf "https://w1.fi/cgit/hostap/plain/hostapd/hostapd.conf") setting). |
| _time\_zone_ | string | no | (none) | Local time zone as specified in 8.3 of IEEE Std 1003.1-2004. |
| _wnm\_sleep\_mode_ | boolean | no | _0_ | WNM-Sleep Mode (extended sleep mode for stations). |
| _bss\_transition_ | boolean | no | _0_ | BSS Transition Management. |

First note that 802.11r is not necessarily needed for [roaming](https://openwrt.org/docs/guide-user/network/wifi/roaming "docs:guide-user:network:wifi:roaming") since most WiFi clients (e.g. phones, tablets, laptops) will roam regardless of access point features. The difference is that roaming without 802.11r will take longer. Without 802.11r roaming for PSK might take 150ms and with EAP 500ms+. With 802.11r roaming is reduced to 15-75ms, see the [forum discussion](https://forum.openwrt.org/t/fast-seamless-roaming-through-ethernet-with-openwrt/182458/7 "https://forum.openwrt.org/t/fast-seamless-roaming-through-ethernet-with-openwrt/182458/7"). So you will likely only see a difference if you are roaming whilst time-sensitive network traffic is being exchanged (e.g. VoIP, video conference, online game, etc.). You are advised to read [the 802.11r section of the roaming guide](https://openwrt.org/docs/guide-user/network/wifi/roaming#r_fast_transition "docs:guide-user:network:wifi:roaming") which details limitations and compatibility issues before enabling 802.11r.

To check if 802.11r is working properly, set log_level to 1 (cf. [Common Options](https://openwrt.org/docs/guide-user/network/wifi/basic#common_options1 "docs:guide-user:network:wifi:basic")) and look for message “_FT authentication already completed - do not start 4-way handshake_” in your system log after roaming.

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _ieee80211r_ | boolean | no | _0_ | Enables fast BSS transition (802.11r) support. |
| _nasid_ | string | no | _(BSSID without colon)_ | PMK-R0 Key Holder identifier (dot11FTR0KeyHolderID). A 1 to 48 octet identifier. |
| _mobility\_domain_ | string | no | _(first 4 bytes of `md5sum` of the SSID)_ | Mobility Domain identifier (dot11FTMobilityDomainID, MDID). MDID is used to indicate a group of APs (within an ESS, i.e., sharing the same SSID) between which a STA can use Fast BSS Transition. 2-octet identifier as a hex string. |
| _r0\_key\_lifetime_ | integer | no | _10000_ | Default lifetime of the PMK-RO in minutes [1-65535]. |
| _r1\_key\_holder_ | string | no | _(BSSID) (hostapd default)_ | PMK-R1 Key Holder identifier (dot11FTR1KeyHolderID). A 6-octet identifier as a hex string. |
| _reassociation\_deadline_ | integer | no | _1000_ | Reassociation deadline in time units (TUs / 1.024 ms, 1000-65535). ![Image 10: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Warning: Some devices do not function properly with the default value of _1000_. Using _20000_ which is the default used on Cisco gear appears to resolve these issues. This will also become the default in the OpenWRT 25.12 series. |
| _r0kh_ | string | no | ff:ff:ff:ff:ff:ff,*,$key | List of R0KHs in the same Mobility Domain. Valid format: <MAC address>,<NAS Identifier>,<256-bit key as hex string> This list is used to map R0KH-ID (NAS Identifier) to a destination MAC address when requesting PMK-R1 key from the R0KH that the STA used during the Initial Mobility Domain Association. Key is generated with thep of auth_secret, so this should be the same for all APs. |
| _r1kh_ | string | no | 00:00:00:00:00:00,00:00:00:00:00:00,$key | List of R1KHs in the same Mobility Domain. Valid format: <MAC address>,<R1KH-ID>,<256-bit key as hex string> This list is used to map R1KH-ID to a destination MAC address when sending PMK-R1 key from the R0KH. This is also the list of authorized R1KHs in the MD that can request PMK-R1 keys. |
| _pmk\_r1\_push_ | boolean | no | _0_ | Whether PMK-R1 push is enabled at R0KH. ![Image 11: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Warning: If WPA3 (SAE) is enabled, setting this will break fast BSS transition (802.11r). |
| _ft\_over\_ds_ | boolean | no | _0_ | Whether to enable FT-over-DS. ![Image 12: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Warning: The previous default value of 1 for “FT over the DS” is known to cause issues especially with Apple devices. Setting this to 0 which instead uses “FT over the Air” is known to fix these issues and is the default as of openwrt [23.05.0](https://github.com/openwrt/openwrt/commit/2984a0420649733662ff95b0aff720b8c2c19f8a "https://github.com/openwrt/openwrt/commit/2984a0420649733662ff95b0aff720b8c2c19f8a"). |
| _ft\_psk\_generate\_local_ | boolean | no | _auto_ | Whether to generate FT response locally for PSK networks. This avoids use of PMK-R1 push/pull from other APs with FT-PSK networks as the required information (PSK and other session data) is already locally available. ![Image 13: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Warning: Do not enable for WPA2/3 mixed mode or WPA3-only (SAE); this will break fast BSS transition (802.11r). Note that Fast Transition will still work as r0kh and r1kh are automatically generated by default, or you may set r0kh & r1kh manually. |

| Name | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| _disassoc\_low\_ack_ | boolean | no | _1_ | Disassociate stations based on excessive transmission failures or other indications of connection loss. This depends on the driver capabilities and may not be available with all drivers. |
| _max\_inactivity_ | integer | no | _300_ | Station inactivity limit in seconds: If a station does not send anything in ap_max_inactivity seconds, an empty data frame is sent to it in order to verify whether it is still in range. If this frame is not ACKed, the station will be disassociated and then deauthenticated. |
| _skip\_inactivity\_poll_ | boolean | no | _0_ | The inactivity polling can be disabled to disconnect stations based on inactivity timeout so that idle stations are more likely to be disconnected even if they are still in range of the AP. |
| _max\_listen\_interval_ | integer | no | _65535_ | Maximum allowed Listen Interval (how many Beacon periods STAs are allowed to remain asleep). |

The _wifi-station_ section allows matching a client (station) based on it's PSK or MAC Address and tagging it with a VLAN ID. It can be used to replicate the behaviour of _wpa\_psk\_file_ in native UCI.

![Image 14: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) WPA3 SAE is supported since 24.10.

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| _iface_ | string | no | Wireless interface this station will be matched for (empty would match all interfaces) |
| _vid_ | integer | no | VLAN ID to assign station to (defaults to no VLAN) |
| _mac_ | string | no | MAC address to match authenticating stations against |
| _key_ | string | yes | PSK to match authenticating stations against |

Example:

config	wifi-station
	option	iface		'iface_radio0'
	option	vid		'10'
	option	mac		'12:34:56:78:90:00'
	option	key		'hunter12'

The _wifi-vlan_ section allows you to map between VLAN tagging on hostapd interfaces and their corresponding networks.

![Image 15: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) If the underlying interface is a DSA interface (Hardware Switch) make sure to configure the VLANs appropiately to guarantee the packets flow further.

| Name | Type | Required | Description |
| --- | --- | --- | --- |
| _iface_ | string | no | Wireless interface this VLAN will be matched for (empty would match all interfaces) |
| _vid_ | integer | yes | VLAN ID to match against |
| _network_ | string | yes | Network interface that this VLAN ID will be assigned |
| _name_ | string | yes | Name for the VLAN entry. Maximum length: 14 - Wi-Fi interface name length |

Example:

config	wifi-vlan
	option	iface		'iface_radio0'
	option	network		'dmz'
	option	vid		'10'
	option	name		'10'

Wireless interfaces are brought up and down with the _wifi_ command. To (re)start the wireless after a configuration change, use _wifi_, to disable the wireless, run _wifi down_. In case your platform carries multiple wireless devices it is possible to start or run down each of them individually by making the _wifi_ command be followed by the device name as a second parameter. Note: The _wifi_ command has an optional first parameter that defaults to _up_ , i.e. start the device. To make the second parameter indeed a second parameter it is mandatory to give a first parameter which can be anything except _down_. E.g. to start the interface _wlan2_ issue: _wifi up wlan2_; to stop that interface: _wifi down wlan2_. If the platform has also e.g. wlan0 and wlan1 these will not be touched by stopping or starting wlan2 selectively.

To rebuild the configuration file, e.g. after installing a new wireless driver, remove the existing wireless configuration (if any) and use the _wifi config_ command:

rm -f /etc/config/wireless
wifi config

The Wi-Fi channel width is the range of frequencies i.e. how broad the signal is for transferring data. Generally speaking, the bigger the channel width, the more data can be transmitted over the signal. But as with everything there are drawbacks. With larger channel widths, interference with others Wi-Fi networks or Bluetooth becomes a much larger issue, and making solid connections becomes much harder as well. Think of it like a highway. The wider the road, the more traffic (data) can pass through. On the other hand, the more cars (routers) you have on the road, the more congested the traffic becomes.

Wi-Fi standard allows 10, 20, 22, 40, 80 and 160 MHz but 10MHz is not used anymore, the 80 and 160 can be used only with 5 GHz frequency, and certain devices not being able to connect to APs with channel widths more than 40Mhz.

By default, the 2.4 GHz frequency uses a 20 MHz channel width. A 20MHz channel width is wide enough to span one channel. A 40 MHz channel width bonds two neighbouring 20 MHz channels together, forming a 40 MHz channel width; therefore, it allows for greater speed and faster transfer rates. One “control” channel functions as the main channel, and the other “extension” as the auxiliary channel. The main channel sends Beacon packets and data packets, and the auxiliary channel sends other packets. The extension channel can either be “above” or “below” the control channel, as long as it doesn't go outside the band. For example, if your control channel is 1, your extension channel has to “above”, because anything below channel 1 would be below the lowest frequency allowed in the 2.4GHz ISM band. The extension channel has to be contiguous with the edge of the control channel, without overlapping.

`HT40+` means that centre frequency of the main 20 MHz channel is higher than that of the auxiliary channel, and `HT40-` otherwise. For example, if the centre frequency 149 and the centre frequency 153 reside on two 20 MHz channels, 149plus indicates that the two 20 MHz channels are bundled to form a 40 MHz channel.

When the HT40 mode is used in the 2.4 GHz frequency band, there is only one non-overlapping channel. Therefore, you are not advised to use the HT40 mode in the 2.4 GHz frequency band.

The default max channel width `VT20` i.e. 20MHz supports a max speed of 150Mbps. Increasing this to 40MHz will increase the maximum theoretical speed to 300Mbps. The catch is that in areas with a lot of Wi-Fi traffic (and Bluetooth etc. which share the same radio frequencies), 40MHz may decrease your overall speed. Devices **should** detect interference when using 40MHz, and drop back to 20MHz. Edit `htmode` options in the file `/etc/config/wireless` and restart the Wi-Fi AP to test various channel widths. Note that option _htmode_ should be set to either `HT40+` (for channels 1-7) or `HT40-` (for channels 5-11) or simply `HT40`.

When using the mac80211 device, you can choose to enable/disable a number of high-throughput capabilities by setting any of the following options in the wifi-device section. Most capabilities are detected and enabled by default (in Barrier Breaker or later).

The following capabilities relate to 802.11n operation, and are enabled when the htmode option is set to any of HT20 HT40 HT40- HT40+ VHT20 VHT40 VHT80 or VHT160. Capabilities supported by a device can be queried with the `iw list` command, and are listed in the “Capabilities” section, refer to [https://w1.fi/cgit/hostap/tree/hostapd/hostapd.conf](https://w1.fi/cgit/hostap/tree/hostapd/hostapd.conf "https://w1.fi/cgit/hostap/tree/hostapd/hostapd.conf") for a description of the options (search for ht_capab on that web page).

| Name | Type | Default | Capability | Description |
| --- | --- | --- | --- | --- |
| ldpc | boolean | 1 | LDPC | LDPC (Low-Density Parity-Check code) capability |
| greenfield | boolean | 0 | GF | Receive Greenfield - treats pre-80211n traffic as noise. ![Image 16: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) Warning: this can cause significant packet collisions and reduction in performance if older pre-n (a/b/g) traffic is present in the local area (including other networks which you don't control); it is disabled by default for a reason. |
| short_gi_20 | boolean | 1 | SHORT-GI-20 | Short GI (guard interval) for 20 MHz |
| short_gi_40 | boolean | 1 | SHORT-GI-40 | Short GI for 40 MHz |
| tx_stbc | integer | 1 | TX-STBC | Transmit STBC (Space-Time Block Coding) |
| rx_stbc | integer | 3 | RX-STBC1 RX-STBC12 RX-STBC123 | Receive STBC: 1 - one spatial stream, 2 - one or two spatial streams, 3 - one, two, or three spatial streams, 0 - disables capability |
| max_amsdu | boolean | 1 | MAX-AMSDU-7935 | Maximum A-MSDU length of 7935 octets (3839 octets if option set to 0) |
| dsss_cck_40 | boolean | 1 | DSSS_CCK-40 | DSSS/CCK Mode in 40 MHz allowed in Beacon, Measurement Pilot and Probe Response frames |

The following capabilities relate to 802.11ac operation, and are enabled when the htmode option is set to any of VHT20, VHT40, VHT80, or VHT160. Capabilities supported by the device can be queried with the `iw list` command and are listed in the “VHT Capabilities” section.

| Name | Type | Default | Capability | Description |
| --- | --- | --- | --- | --- |
| rxldpc | boolean | 1 | RXLDPC | Supports receiving LDPC coded pkts |
| short_gi_80 | boolean | 1 | SHORT-GI-80 | Supports reception of packets transmitted with TXVECTOR params format equal to VHT and CBW = 80Mhz |
| short_gi_160 | boolean | 1 | SHORT-GI-160 | Supports reception of packets transmitted with TXVECTOR params format equal to VHT and CBW = 160Mhz |
| tx_stbc_2by1 | boolean | 1 | TX-STBC-2BY1 | Supports transmission of at least 2×1 STBC ![Image 17: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) currently ignored in trunk |
| su_beamformer | boolean | 1 | SU-BEAMFORMER | Single user beamformer |
| su_beamformee | boolean | 1 | SU-BEAMFORMEE | Single user beamformee |
| mu_beamformer | boolean | 1 | MU-BEAMFORMER | Supports operation as an MU beamformer |
| mu_beamformee | boolean | 1 | MU-BEAMFORMEE | Supports operation as an MU beamformee |
| vht_txop_ps | boolean | 1 | VHT-TXOP-PS | 0 = VHT AP doesn't support VHT TXOP PS (Power Save) mode (OR) VHT STA not in VHT TXOP PS mode, 1 = VHT AP supports VHT TXOP PS mode (OR) VHT STA is in VHT TXOP power save mode |
| htc_vht | boolean | 1 | HTC-VHT | STA supports receiving a VHT variant HT Control field. |
| rx_antenna_pattern | boolean | 1 | RX-ANTENNA-PATTERN | Rx antenna pattern does not change during the lifetime of an association |
| tx_antenna_pattern | boolean | 1 | TX-ANTENNA-PATTERN | Tx antenna pattern does not change during the lifetime of an association |
| vht_max_a_mpdu_len_exp | integer | 7 | MAX-A-MPDU-LEN-EXP<0-7> | Indicates the maximum length of A-MPDU pre-EOF padding that the STA can recv |
| vht_max_mpdu | integer | 11454 | MAX-MPDU-7991 MAX-MPDU-11454 | Maximum MPDU length |
| rx_stbc | integer | 4 | 0 - not supported, 1 - RX-STBC-1, 2 - RX-STBC-12, 3 - RX-STBC-123, 4 - RX-STBC-1234 | Supports reception of PPDUs using STBC: 1 - one spatial stream, 2 - one or two spatial streams, etc. ![Image 18: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) currently used incorrectly in trunk |
| vht_link_adapt | integer | 3 | VHT-LINK-ADAPT<0-3> | TA supports link adaptation using VHT variant HT Control field |
| vht160 | integer | 2 | VHT160 VHT160-80PLUS80 | Supported channel widths: 0 - 160MHz and 80+80 MHz not supported, 1 - 160 MHz supported, 2 - 160MHz and 80+80 MHz supported |

In many countries, operating Wi-Fi devices on some or all channels in the 5GHz band requires radar detection and [DFS](https://openwrt.org/docs/techref/dfs "docs:techref:dfs")[(explanation)](http://wifi-insider.com/wlan/dfs.htm "http://wifi-insider.com/wlan/dfs.htm"). If you define a channel in your wireless config that requires DFS according to your country regulations, the 5GHz radio device won’t start up unless the firmware image is able to provide DFS support (i.e. it is both included and enabled). More technical details of the Linux implementation can be found [here](https://wireless.wiki.kernel.org/en/developers/DFS "https://wireless.wiki.kernel.org/en/developers/DFS"). DFS works as follows in Linux: The driver detects radar pulses and reports this to nl80211 where the information is processed. If a series of pulses matches one of the defined radar patterns, this will be reported to the user space application (e.g. hostapd) which in turn reacts by switching to another channel.

The following configuration specifies channel 104 which needs DFS support as implicitly stated with country code DE:

config	wifi-device		'radio0'
	option	type		'mac80211'
	option	channel		'104'
	option	hwmode		'11a'
	option	path		'pci0000:00/0000:00:00.0'
	option	htmode		'HT20'
	option	country		'DE'
 
config	wifi-iface
	option	device		'radio0'
	option	network		'lan'
	option	mode		'ap'
	option	ssid		'OpenWrt'
	option	encryption	'none'
You can check the country (regulatory domain) your Wi-Fi card thinks it must conform to with

iw reg get
If in doubt, double check your hostapd-phy.conf to make sure it contains the following values, and that your country code is set:

country_code=DE
ieee80211n=1
ieee80211d=1
ieee80211h=1
hw_mode=a
If radar detection is working, DFS channels will show up like this (here for Belgium, _iw phy1 info_ output trimmed):

Frequencies:
* 5220 MHz [44] (17.0 dBm)
* 5240 MHz [48] (17.0 dBm)
* 5260 MHz [52] (20.0 dBm) (radar detection)
DFS state: usable (for 2155257 sec)
DFS CAC time: 60000 ms
* 5280 MHz [56] (20.0 dBm) (radar detection)
DFS state: usable (for 2155257 sec)
DFS CAC time: 60000 ms
![Image 19: :!:](https://openwrt.org/lib/images/smileys/exclaim.svg) When DFS is on, there will be a delay before the interface is enabled (e.g. after reboot). During this time period (often 60 seconds, and determined by local reglations) luci will report the interface is disabled. This time period is used to detect the presence of other signals on the channel (Channel Availability Check Time). This process can be monitored with:

logread -f
If you select a channel that requires DFS in your country and enable HT40, this may result in the **DFS start_dfs_cac() failed** error (visible with logread):

Configuration file: /var/run/hostapd-phy1.conf
wlan1: interface state UNINITIALIZED->COUNTRY_UPDATE
wlan1: interface state COUNTRY_UPDATE->HT_SCAN
wlan1: interface state HT_SCAN->DFS
wlan1: DFS-CAC-START freq=5680 chan=136 sec_chan=-1, width=0, seg0=0, seg1=0, cac_time=60s
DFS start_dfs_cac() failed, -1
Interface initialization failed
wlan1: interface state DFS->DISABLED
wlan1: AP-DISABLED
hostapd_free_hapd_data: Interface wlan1 wasn't started
Changing your configuration to HT20 should resolve this.
