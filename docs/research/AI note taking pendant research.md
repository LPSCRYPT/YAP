# Speak Omi's protocol, then beat it on Wi-Fi

Atharv and Zoo should build their pendant as an **Omi-compatible BLE audio device on ESP-IDF**: an I2S mic feeding 16 kHz Opus that is always written to microSD first, streamed over BLE when a phone is in range, and bulk-uploaded over Wi-Fi when it is not. The two MIT-licensed projects that make this a weeks-long job rather than a months-long one are **xiaozhi-esp32**, which already ships a working board definition for their exact Waveshare ESP32-S3-Touch-LCD-1.46, and **BasedHardware/omi**, whose documented GATT protocol and ESP32-S3 "omiGlass" firmware let the stock Omi app act as their companion app on day one. The commercial market (Plaud, Bee, Omi, Fieldy, with Limitless absorbed by Meta) has settled on a common pattern: a BLE accessory relays audio through a phone to cloud speech-to-text and an LLM, sold as $50–250 hardware plus a free tier of 150–300 minutes and an unlimited plan at $20–30/month. That gives the students a clear target to match, and three gaps the market leaves open: Hindi-English code-switched speech, local-first or self-hosted processing that cannot be "rug-pulled", and direct Wi-Fi sync, which is the ESP32's natural strength. The Waveshare board is a capable but power-hungry prototype. With the screen dark, a 500 mAh cell gives an estimated **~7 h of SD-only recording or ~4–5 h of BLE streaming**, against 20 h for Plaud's NotePin. Running costs are dominated by speech-to-text at roughly **$0.10–0.36 per audio hour**, while LLM summarization costs well under a cent per hour with small models. The first two weeks should produce a record-to-SD-then-laptop pipeline that A/B-tests real Hinglish audio across STT vendors, because microphone quality and language accuracy are the two biggest unknowns.

## Commercial pendants converge on BLE, a phone app and a $20–30 subscription

The category has split three ways. **Press-to-record professional recorders** (Plaud, Fieldy) are alive and growing. **Always-on "memory" pendants** have been bought by big tech: Meta acquired Limitless and ended Pendant sales on Dec 5, 2025 ([9to5Mac](https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/)), and Amazon bought Bee, which still ships ([TechCrunch](https://techcrunch.com/2026/01/12/why-amazon-bought-bee-an-ai-wearable/)). **Companion devices** (Friend, the Sandbar Stream ring) chase a different use case. Under the branding, almost every product is the same machine: a BLE accessory relaying audio through a phone app to cloud ASR and LLMs.

| Product | Status (Oct 2026) | Hardware price | Subscription | Battery (real use) | Capture model and notable features |
|---|---|---|---|---|---|
| **Plaud NotePin / NotePin S / Note Pro** | Market leader; launched in India | $159 / $179 / $189 | Free 300 min/mo; Pro 1,200 min $17.99/mo; Unlimited $29.99/mo | NotePin up to 20 h; Note Pro up to 50 h "Endurance" | Press-to-record. Note Pro has a 4-mic beamforming array, 16.4 ft pickup, AMOLED screen and "Press to Highlight"; NotePin S adds Apple Find My ([Plaud](https://www.plaud.ai/blogs/articles/plaud-anniversary), [Plaud India](https://in.plaud.ai/blogs/news/plaud-launches-in-india-bringing-conversational-intelligence-to-a-new-generation-of-india-s-ambitious-professionals)) |
| **Limitless Pendant** | Acquired by Meta; sales ended Dec 2025 | was $99 | Free 10 h/mo; Unlimited $29/mo (one source says $49) | 6–7 h continuous recording vs 100 h advertised (vendor review) | Always-on; local buffering, Wi-Fi/BLE sync. Service ended in the EU, UK and five other markets, and user data there was deleted ([9to5Mac](https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/), [TechCrunch](https://techcrunch.com/2025/11/21/the-hottest-ai-wearables-and-gadgets-you-can-buy-right-now), [fast.io](https://www.fast.io/resources/limitless-ai-review-2026.md)) |
| **Bee (Amazon)** | Shipping; shown at CES 2026 | $49.99 | Conflicting: "none required" vs $19/mo | Up to 7 days claimed (secondary) | Always-on clip or wristband with 2 mics and a mute button. **Discards audio after transcription**. Gmail, Calendar and Apple Health integrations; iOS only ([TechCrunch](https://techcrunch.com/2026/01/12/why-amazon-bought-bee-an-ai-wearable/), [Notebookcheck](https://www.notebookcheck.net/Amazon-acquires-Bee-maker-of-budget-friendly-AI-wearable-without-mandatory-subscription.1065535.0.html)) |
| **Omi (BasedHardware)** | Shipping; open source | $89 (TechCrunch) vs $129–179 (secondary) | Free plan; Unlimited $29.99/mo (secondary) | 10–14 h (secondary); a battery-drain bug has been reported | Always-on; open BLE protocol, SDKs, plugin app store ([Omi docs](https://docs.omi.me/docs/hardware/DevKit1), [layer3labs](https://www.layer3labs.io/guides/best-ai-wearable-pendants-2026), [Omi Featurebase](https://omi.featurebase.app/p/l-pendant-battery-draining-way-faster)) |
| **Fieldy** | Shipping | $89–149 | Free 150 min/mo; Plus $12.99; Unlimited $19.99/mo | ~3 days claimed | 99 languages, voice-fingerprint speaker ID. Criticized for BLE drops and **no recording indicator** ([autonomous.ai](https://www.autonomous.ai/en-NL/ourblog/fieldy-ai-review)) |
| **Friend 2.0** | Relaunched Jul 2026 | $249 | $9.99/mo to keep memories past 30 days | n/a | A companion rather than a note-taker; adds a speaker. Met public backlash ([The Next Web](https://thenextweb.com/news/friend-ai-pendant-relaunch-speaker-double-price)) |
| **Sandbar Stream ring** | Pre-order; shipping not confirmed | $249–299 | 3 months of Pro free, then limited | "All day" | Hold-to-record touchpad, iOS first ([Tom's Guide](https://www.tomsguide.com/wellness/smart-rings/new-wearable-aims-to-be-an-ai-powered-decoder-ring-for-your-life-heres-how)) |
| **NeoSapien Neo 1 (India)** | Shipping | ~₹10,000 | n/a | n/a | Claims 40+ Indic languages; cloud only; LED while listening ([Inc42](https://inc42.com/startups/ai-wearables-neosapien-make-the-most-of-this-wave/)) |
| **Humane AI Pin** | Dead (Feb 2025) | was $700 | — | — | Servers shut down and devices bricked: the cautionary tale ([Tom's Guide](https://www.tomsguide.com/ai/the-humane-ai-pin-is-officially-dead-and-hp-is-picking-up-humanes-leftovers)) |

Reviews show what users will judge the students' device on. Users praise **capturing in-person conversations that meeting bots miss, near-perfect single-speaker transcripts, and automatic action items**. They complain about **battery claims versus reality** (Limitless advertised 100 h but recorded for 6–7 h), **speaker mislabeling, garbled mixed-language transcripts**, BLE pairing drops, cluttered apps and subscription cost ([fast.io](https://www.fast.io/resources/limitless-ai-review-2026.md), [autonomous.ai](https://www.autonomous.ai/en-NL/ourblog/fieldy-ai-review)). Bee's audio-discarding design is good for privacy, but it means users cannot check transcripts against the recording ([TechCrunch](https://techcrunch.com/2026/01/12/why-amazon-bought-bee-an-ai-wearable/)). Investors are funding privacy-by-design: a former Apple engineer raised $5M for a pendant that **records only the wearer's voice** ([MaC VC](https://macventurecapital.com/former-apple-engineer-raises-5m-for-a-note-taking-pendant-that-only-records-your-voice/)). Plaud's arrival in India and NeoSapien's ₹10,000 device show the local market is live but, in NeoSapien's words, "yet to be crowded" ([Inc42](https://inc42.com/startups/ai-wearables-neosapien-make-the-most-of-this-wave/)).

The baseline feature set users now treat as standard is transcripts, summaries, action items, speaker labels, searchable memory and calendar hooks. Features that still set a product apart are a physical record or highlight button, a visible recording indicator, user control over whether raw audio is kept, data export, and a choice of LLM.

## Three MIT codebases cover most of the build

The students should not write a pendant stack from scratch, and they should not fork one wholesale either. Each of the strong open-source bases solves a different layer.

**BasedHardware/omi** (MIT, ~13.8k stars, very active) contains a Flutter mobile app, a FastAPI backend, nRF/Zephyr pendant firmware, and, most usefully, `omiGlass/firmware`: an **ESP32-S3 implementation of the Omi BLE protocol** built for the Seeed XIAO ESP32S3 Sense, the board the students already own ([GitHub](https://github.com/BasedHardware/omi), [platformio.ini](https://raw.githubusercontent.com/BasedHardware/omi/main/omiGlass/firmware/platformio.ini)). The protocol is small. Audio service `19B10000-E8F2-537E-4F6C-D104768A1214` sends notifications on `…0001`, and each notification carries a 3-byte header: a 2-byte little-endian packet counter plus a 1-byte fragment index. Frames are split at MTU−3 bytes. A codec ID is exposed on `…0002`, and current firmware sends **Opus, 16 kHz mono, 20 ms/320-sample frames, codec ID 21, 32 kbps VBR, complexity 3** ([transport.c](https://raw.githubusercontent.com/BasedHardware/omi/main/omi/firmware/omi/src/lib/core/transport.c), [omiGlass config.h](https://raw.githubusercontent.com/BasedHardware/omi/main/omiGlass/firmware/src/config.h)). The Omi app already accepts third-party wearables and offers webhooks, a realtime raw-PCM audio webhook and a custom-STT hook ([bt_device.dart](https://raw.githubusercontent.com/BasedHardware/omi/main/app/lib/backend/schema/bt_device/bt_device.dart), [AudioStreaming.mdx](https://raw.githubusercontent.com/BasedHardware/omi/main/docs/doc/developer/apps/AudioStreaming.mdx)). A Waveshare board that exposes this service should therefore get transcription, summaries and memories in the stock Omi app with zero app code. One trap: the protocol docs list PCM codec IDs 0/10/11, but the current app only decodes IDs 1, 20 and 21, so **use Opus (21) and never rely on raw PCM** ([omi_connection.dart](https://raw.githubusercontent.com/BasedHardware/omi/main/app/lib/services/devices/connectors/omi_connection.dart)).

**78/xiaozhi-esp32** (MIT, ~31.9k stars) has a first-party target, `BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_LCD_1_46`, which covers both the 1.46 and the 1.46B. Its board files are effectively a verified pin map and driver set: an I2S mic on WS 2 / SCK 15 / DIN 39, a PCM5101 speaker on 47/48/38, the SPD2010 QSPI display driver, the TCA9554 expander, the PWR button on GPIO6 and power-hold on GPIO7 ([config.h](https://raw.githubusercontent.com/78/xiaozhi-esp32/main/main/boards/waveshare/esp32-s3-touch-lcd-1.46/config.h), [board .cc](https://raw.githubusercontent.com/78/xiaozhi-esp32/main/main/boards/waveshare/esp32-s3-touch-lcd-1.46/esp32-s3-touch-lcd-1.46.cc)). Xiaozhi itself is a Wi-Fi conversational assistant (WebSocket or MQTT+UDP, 60 ms Opus frames, ESP-SR wake word, LVGL UI). It **requires ESP-IDF v6.0.1+** and defaults to the xiaozhi.me cloud ([README](https://raw.githubusercontent.com/78/xiaozhi-esp32/main/README.md)). Treat it as a parts bin for board bring-up, not as the product.

**Espressif's own components** handle the signal layer. ESP-SR provides the audio front end, the VADNet neural voice-activity detector (released Feb 2025 to replace WebRTC VAD) and WakeNet ([ESP-SR README](https://raw.githubusercontent.com/espressif/esp-sr/master/README.md)). `esp_audio_codec`, which xiaozhi uses, or the esphome `micro-opus` component provides Opus, and `ble_ota` handles firmware updates over BLE ([idf_component.yml](https://raw.githubusercontent.com/78/xiaozhi-esp32/main/main/idf_component.yml), [ble_ota](https://components.espressif.com/components/espressif/ble_ota/versions/0.1.16/examples/ble_ota)).

| Project | License | What to reuse | Caveat |
|---|---|---|---|
| omi `omiGlass/firmware` (ESP32-S3) | MIT ([LICENSE](https://raw.githubusercontent.com/BasedHardware/omi/main/LICENSE)) | GATT UUIDs, codec-21 framing, NimBLE setup; a closest-template `app.cpp` | Arduino framework; depends on the **retired** arduino-libopus ([README](https://raw.githubusercontent.com/pschatzmann/arduino-libopus/main/README.md)) |
| omi `omi/firmware` (nRF/Zephyr) | MIT | Logic reference: MTU-aware fragmentation, offline-storage service | Zephyr APIs, so not portable to ESP-IDF |
| omi `app/` (Flutter) | MIT | Day-1 companion app; later a fork base | Large and Firebase-coupled; the "Omi" trademark is not licensed |
| omi `backend/` (FastAPI) | MIT | Pipeline design: 120 s silence segmentation, structured extraction, memories | Self-hosting needs Firebase/GCP, Redis, Pinecone and Typesense ([Backend_Setup](https://raw.githubusercontent.com/BasedHardware/omi/main/docs/doc/developer/backend/Backend_Setup.mdx)) |
| xiaozhi-esp32 Waveshare 1.46 board dir | MIT ([LICENSE](https://raw.githubusercontent.com/78/xiaozhi-esp32/main/LICENSE)) | Pin map, SPD2010/LVGL init, buttons, power hold | IDF v6-only; Wi-Fi-first; no BLE audio code |
| xinnan-tech/xiaozhi-esp32-server | MIT ([LICENSE](https://raw.githubusercontent.com/xinnan-tech/xiaozhi-esp32-server/main/LICENSE)) | Python server patterns: Silero VAD, FunASR, any OpenAI-compatible LLM | Built for conversational turns, not note archives |
| ESP-SR / ESP-ADF | Espressif MIT, Espressif chips only ([LICENSE](https://raw.githubusercontent.com/espressif/esp-sr/master/LICENSE)) | VADNet gating, AFE noise suppression, optional wake word | Cannot be ported to an nRF later; ESP-ADF v3 needs IDF 5.5.2+ |
| Owl | MIT ([LICENSE](https://raw.githubusercontent.com/OwlAIProject/Owl/main/LICENSE)) | Server ideas: VAD conversation endpointing, speaker verification, Ollama | Smaller project (~658 stars) |
| SenseCAP Watcher SDK | Apache-2.0 ([LICENSE](https://raw.githubusercontent.com/Seeed-Studio/SenseCAP-Watcher-Firmware/main/LICENSE)) | Watcher drivers, if that board is used later | Watcher is a desk device |
| whisper.cpp / faster-whisper | MIT / MIT ([1](https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/LICENSE), [2](https://raw.githubusercontent.com/SYSTRAN/faster-whisper/master/LICENSE)) | Free local STT for Phase 0 and a privacy mode | Hinglish accuracy unverified |
| Vosk / NVIDIA NeMo (Parakeet) | Apache-2.0 ([Vosk](https://raw.githubusercontent.com/alphacep/vosk-api/master/COPYING), [NeMo](https://raw.githubusercontent.com/NVIDIA/NeMo/main/LICENSE)) | Self-hosted STT; Omi itself now self-hosts Parakeet | Parakeet needs a GPU |
| Silero VAD / pyannote.audio | MIT / MIT code ([Silero](https://raw.githubusercontent.com/snakers4/silero-vad/master/LICENSE), [pyannote](https://raw.githubusercontent.com/pyannote/pyannote-audio/develop/LICENSE)) | Server VAD; diarization via `community-1` | pyannote model weights are gated on Hugging Face; terms not checked |
| Adeus | **CC BY-NC-ND** ([LICENSE](https://raw.githubusercontent.com/adamcohenhillel/ADeus/main/LICENSE)) | Ideas only | No commercial use, no derivatives |
| OpenInterpreter 01 | **AGPL-3.0** ([LICENSE](https://raw.githubusercontent.com/OpenInterpreter/01/main/LICENSE)) | Ideas only | Network use triggers source disclosure |
| ESPHome C++ / HA Voice PE | **GPLv3** for C++ ([LICENSE](https://raw.githubusercontent.com/esphome/esphome/dev/LICENSE)) | Ideas only | Copying code makes the firmware GPL |

The licensing picture favours a commercial future. Everything on the recommended path is MIT, Apache or Espressif-MIT, so keeping copyright notices is the only obligation. The real constraint is the **Omi trademark**: the device must not call itself "Omi". This is less awkward than it sounds, because omiGlass advertises as "OMI Glass" and still works with the app, which suggests discovery is not strictly tied to the name "Omi". That still needs testing on hardware ([omiGlass config.h](https://raw.githubusercontent.com/BasedHardware/omi/main/omiGlass/firmware/src/config.h)).

## The Waveshare 1.46 works as a prototype if its screen stays dark

The board packs an ESP32-S3R8 (8 MB PSRAM, 16 MB flash, Wi-Fi 4, BLE 5), a 412×412 round touch display, one I2S mic, a PCM5101 DAC with speaker, a QMI8658 IMU, a PCF85063 RTC, a microSD slot and a LiPo charger, all for **$26.99** ([Waveshare](https://waveshare.com/esp32-s3-touch-lcd-1.46b.htm?sku=29565), [Waveshare docs](https://docs.waveshare.com/ESP32-S3-Touch-LCD-1.46)). Every pendant subsystem has a home on it, but each comes with a catch.

| Pendant function | Waveshare 1.46 resource | Implication |
|---|---|---|
| Microphone | 1× I2S mic, BCK 15 / WS 2 / DIN 39, data on the right slot; part number unpublished ([LCD Wizard](https://lcdwizard.com/boards/waveshare-s3-touch-lcd-146b)) | Use `i2s_std` RX at 16 kHz in 32-bit mono slots and shift down to 16-bit (estimate). SNR is unknown, so test pickup across a table early. GPIO39 doubles as the JTAG MTCK pin (inference). |
| Audio codec | ESP32-S3 software Opus | The fixed-point build encodes at **RTF 0.20–0.26** (complexity 0, 10–32 kbps). **The floating-point build is slower than real time (RTF 1.53)** ([micro-opus benchmark](https://components.espressif.com/components/esphome/micro-opus/versions/0.4.1/examples/encode_benchmark)) |
| BLE streaming | BLE 5, measured **0.73 Mbit/s on 1M PHY, 1.35 Mbit/s on 2M PHY** between two ESP32-S3s ([Espressif FAQ](https://docs.espressif.com/projects/esp-faq/en/latest/software-framework/bt/ble.html)) | Opus at 16–32 kbps uses a few percent of that. Phone links deliver much less, so raw PCM is risky |
| Wi-Fi sync | 2.4 GHz b/g/n, ceramic antenna plus IPEX option | Bulk upload of SD backlog: the differentiator nRF-based Omi lacks |
| Storage | microSD in **SPI mode only** (D1/D2 unwired; CS via expander EXIO3) ([Waveshare docs](https://docs.waveshare.com/ESP32-S3-Touch-LCD-1.46)) | Still far faster than the 2–4 KB/s Opus write rate. Use FAT32 cards of 32 GB or less |
| Battery | MX1.25 LiPo header, unnamed charger, **GPIO8 battery ADC (÷3), GPIO7 power-hold latch** ([LCD Wizard](https://lcdwizard.com/boards/waveshare-s3-touch-lcd-146b)) | No battery included. GPIO7 gives a true-off state. Charge current is unpublished |
| UI | 1.46" display, backlight on GPIO5 (PWM), touch, BOOT/PWR buttons, IMU | Keep the backlight off. Wake on button or IMU tap for status, timer and sync state |
| Clock | PCF85063 RTC with backup-cell header | Timestamps for offline segments, set from the phone at connect |

The numbers that size the design are simple. Raw 16 kHz/16-bit PCM is **256 kbps (32 KB/s, ~115 MB/h)**. IMA-ADPCM is 64 kbps (~29 MB/h). **Opus at 16 kbps is ~7.2 MB/h**, and at Omi's 32 kbps about 14 MB/h. A 32 GB card therefore holds thousands of hours, so storage is a non-issue; the real risks are FAT corruption on power loss and write-latency spikes. All of these figures are arithmetic estimates from the notes, not measurements.

Power is the hard constraint. No one has published current measurements for this board. The nearest anchor is the XIAO ESP32S3 Sense, which uses the same chip and measured **~54 mA average for mic plus SD writing, ~102 mA with BLE active and ~110 mA with Wi-Fi active** on battery ([Core Electronics / Seeed figures](https://core-electronics.com.au/seeed-studio-xiao-esp32s3-54467.html.plain.md)). The table below adds a guessed 5–15 mA for the Waveshare's extra chips and treats 85% of rated capacity as usable. Every figure is an estimate to be replaced by a USB power-meter reading in week one.

| LiPo | SD-only recording (~62 mA) | BLE Opus stream (~90 mA) | Wi-Fi stream (~125 mA) |
|---|---|---|---|
| 300 mAh | ~4 h | ~2.8 h | ~2 h |
| 500 mAh | ~6.9 h | ~4.7 h | ~3.4 h |
| 800 mAh | ~11 h | ~7.6 h | ~5.4 h |
| 1000 mAh | ~13.7 h | ~9.4 h | ~6.8 h |

A lit display probably adds another 30–80 mA, which would cut these figures by roughly 40%. That is why the screen must be a glance-and-sleep surface, not an always-on face. To come close to commercial benchmarks (Limitless's real 6–7 h, NotePin's 20 h), the firmware needs several techniques together. It should run the CPU at 80–160 MHz with automatic light sleep between I2S DMA buffers. It should gate encoding and radio with VAD, which roughly halves radio time at a 50% speech duty cycle. It should send BLE in bursts after buffering 1–2 s, use a longer connection interval, and use Wi-Fi only when charging or for short bursts. The Omi-class nRF chips draw several times less during BLE streaming. That is a general inference rather than a measured head-to-head result, but it explains why Omi's consumer device uses an nRF5340 with two TDK T5838 PDM mics on a 21 mm board ([Omi docs](https://docs.omi.me/doc/hardware/consumer/electronics)).

The physical form follows from the panel. A 1.46" round display implies an outline of roughly 40–42 mm, so with a 500 mAh cell the pendant ends up at an estimated **40–45 mm across, 12–18 mm thick and 30–45 g**. That is fine on a lanyard and heavy on a shirt clip. The enclosure needs a mic port hole of at least 1 mm aligned with the mic, and the design must reconcile two directions: the display faces outward while the mic needs to face the speaker.

The other two boards have narrower roles. The **XIAO ESP32S3 Sense** is the exact target of omiGlass firmware. Flashing omiGlass on it is a near-free way to prove the Omi-app path before porting the protocol to the Waveshare, and it remains the best candidate for a later small, display-less "v2" clip. The **SenseCAP Watcher** (400 mAh battery, camera, Himax AI co-processor, xiaozhi-supported) is a desk device, so it belongs in the plan as a future home base or charging dock, not as a wearable ([Seeed wiki](https://wiki.seeedstudio.com/watcher_hardware_overview/)).

## Store-and-forward Opus with a thin server is the architecture to build

The recommended system has four tiers, and each one's job is clear:

```
 PENDANT (ESP32-S3, ESP-IDF)                PHONE (Flutter)                SERVER (FastAPI + Supabase)
 I2S mic 16 kHz ─► VADNet gate ─► Opus 20 ms ─┬─► SD: 1-min segments + manifest (always)
                                              ├─► BLE GATT notify (Omi codec 21) ──► receive, persist Opus ──► HTTPS chunk upload
                                              └─► Wi-Fi HTTPS bulk upload of backlog (home/campus Wi-Fi) ─────────────────┐
 RTC timestamps · seq numbers · LED/mute                                                                                 ▼
 BLE sync control point (LIST/ACK)       foreground service / iOS bluetooth-central       STT (batch) ─► diarize ─► LLM JSON
                                         local SQLite cache                               Postgres + pgvector ─► "ask my memories"
```

On the **pendant**, the core rule is that audio is always written to SD before anything else happens. Each Opus frame gets a 32-bit sequence number, a boot ID and an RTC timestamp, and frames are grouped into roughly 1-minute segment files listed in a manifest that records which segments have been uploaded. Omi's 16-bit packet counter wraps after about 22 minutes, which is too short to index an offline backfill, so it stays only as the live-stream header. Live notifications use the Omi audio service, so the stock app works. A custom sync control point (list segments since the last ACK, stream them, ACK ranges, then mark them uploaded) handles backfill. Wi-Fi HTTPS upload sends the same segments directly to the server whenever a known network is in range. Pairing should use LE Secure Connections bonding with encrypted-only characteristics. For updates, ESP-IDF dual OTA partitions with rollback come first, then `esp_https_ota` over Wi-Fi, then Espressif's `ble_ota`, which sends 4 KB sectors with CRC16 and supports pre-encrypted images ([ble_ota](https://components.espressif.com/components/espressif/ble_ota/versions/0.1.16/examples/ble_ota)).

One decision has to be made up front: the toolchain version. Xiaozhi's board files need IDF v6, Waveshare's own demos were written for IDF 5.x, and ESP-ADF v3 needs 5.5.2+ ([Waveshare wiki](https://www.waveshare.com/wiki/ESP32-S3-Touch-LCD-1.46B), [ESP-ADF README](https://raw.githubusercontent.com/espressif/esp-adf/master/README.md)). The students should pick one IDF release in week one, preferably v6.x so the xiaozhi board files drop in cleanly, then confirm that NimBLE, `ble_ota` and the Opus component all build on it.

The **server** should start thin: Supabase for auth, Postgres with pgvector and storage, plus a small FastAPI worker that runs STT, diarization, LLM extraction and embedding on uploaded segments. Omi's production stack (Firestore, Pinecone, Redis, GCS, WebSocket streaming to `/v4/listen`) is the proven end state, but it is heavier than a two-person team needs ([Omi backend deep dive](https://docs.omi.me/doc/developer/backend/backend_deepdive.md)). A server matters even early on for three reasons: API keys cannot live safely in an app binary, batch jobs need retries, and the Android and iOS apps will later share one backend. Chunked HTTPS uploads are more robust than a long-lived WebSocket on patchy Indian mobile data, and they work with batch STT pricing, which is cheaper than streaming. Conversation boundaries can borrow Omi's **120-second silence timeout**. After that timeout, a single structured-output LLM call produces the title, summary, action items (owner, due date, source timestamp), calendar events, durable memories, people, the language detected and a "discard" flag for TV or background chatter. Passing existing memories into that call and asking only for new facts keeps duplicates down ([Omi backend deep dive](https://docs.omi.me/doc/developer/backend/backend_deepdive.md)).

Speech-to-text is the one material running cost, and language accuracy is the main factor in choosing a vendor.

| STT option | Batch $/audio-hr | Streaming $/hr | Diarization | Est. cost for 60 h/month (2 h/day) |
|---|---|---|---|---|
| Soniox | $0.10 | $0.12 | Included; claims mid-sentence Hindi↔English switching ([Soniox](https://soniox.com/speech-to-text/hindi)) | ~$6–7 |
| AssemblyAI Universal-2 | $0.15 | $0.15 | +$0.02/hr ([AssemblyAI](https://www.assemblyai.com/pricing.md)) | ~$10 |
| Speechmatics Melia 1 | $0.129 | $0.24 | ? | ~$8; free 50 h/month (3rd-party tracker, [usagepricing](https://usagepricing.com/blueprint/activity/speechmatics-2026-07-06-realtime-stt-price-cut)) |
| ElevenLabs Scribe v2 | $0.22 | $0.39 | not stated ([ElevenLabs](https://elevenlabs.io/pricing/api)) | ~$13 |
| Deepgram Nova-3 multilingual | $0.312 | $0.552 list | ~+$0.12/hr ([diyai.io](https://diyai.io/ai-tools/speech-to-text/deepgram-pricing-2026/)) | ~$19 |
| OpenAI gpt-4o-transcribe / mini | $0.36 / $0.18 | — | diarize variant same price ([CostGoat](https://costgoat.com/pricing/openai-transcription)) | ~$22 / ~$11 |
| Sarvam (India) | ₹29.40 (₹35.40 diarized) | ₹29.40 | Batch only ([Sarvam](https://docs.sarvam.ai/api/pricing.md)) | ~₹1,760–2,120 |
| faster-whisper / whisper.cpp (self-hosted) | $0 + compute | — | via pyannote | $0 on a laptop |

LLM cost barely registers by comparison. An hour of speech is roughly 12–15k tokens, so one summary call costs about **$0.002 on Claude Haiku 5.5 or Gemini 2.5 Flash-Lite and about $0.045 on Claude Sonnet 5.5** (estimates based on list prices of $0.10/$0.50 and $2/$10 per million tokens; [Anthropic pricing](https://www.anthropic.com/pricing), [morphllm](https://www.morphllm.com/gemini-api-pricing)). Devanagari text tokenizes less efficiently, which could multiply that by 1.5–3×. The sensible split is a cheap model for per-conversation extraction and a stronger one for weekly digests and "ask my memories" Q&A. Even daily Sonnet use costs only about $1–3 per user per month. The levers that matter are batch rather than streaming STT and VAD gating, so silence is never uploaded. Development can run at close to $0 on free credits: Deepgram $200, AssemblyAI $50, Speechmatics 50 h/month and Sarvam ₹100 ([AssemblyAI](https://www.assemblyai.com/pricing.md), [Sarvam](https://docs.sarvam.ai/api/pricing.md)). One caution for real users: free LLM tiers such as Gemini AI Studio may use the content to improve the provider's products, so real users' audio belongs on paid, no-training tiers ([morphllm](https://www.morphllm.com/gemini-api-pricing)).

## A four-phase MVP path that starts with an SD-card recorder

The sequencing principle is to **prove the audio and the prompts before building anything mobile**. The roadmap's effort estimates are judgment rather than sourced benchmarks.

| Phase | Duration (est.) | Build | Exit criterion |
|---|---|---|---|
| **0: Recorder + laptop pipeline** | 1–2 weeks | ESP-IDF firmware on the Waveshare: I2S mic → 1-minute timestamped WAV/Opus files on SD → Wi-Fi HTTP POST to a laptop FastAPI script. A Python pipeline runs faster-whisper plus 2–3 cloud STT APIs → LLM JSON summary → Markdown + SQLite | STT vendor chosen on real Hinglish audio; prompt v1; measured current draw and mic pickup distance |
| **1: BLE device + Android app** | 3–5 weeks | NimBLE GATT server with Omi audio service (codec 21) + Battery `0x180F` + DIS `0x180A` + custom sync control point; validate with the stock Omi app. Minimal Flutter Android app: scan/bond, receive, persist Opus, `connectedDevice` foreground service, upload to Supabase + FastAPI worker; seq/ACK backfill | A full day of capture with phone disconnects loses no audio |
| **2: Notes product** | 3–4 weeks | VAD-based conversation segmentation (120 s), summaries, action items, memories; pgvector "ask my memories" with timestamp citations; daily digest; Hindi/English output toggle; on-device screen showing record state, timer and sync status | Students use it daily for two weeks and keep using it |
| **3: Polish + iOS** | ongoing | iOS from the same Flutter codebase (bluetooth-central, state restoration, TestFlight); Wi-Fi HTTPS OTA, then BLE OTA; Wi-Fi bulk sync; retention, delete-all and export; LED/mute hardware; store and DPDP prep; optional on-device Whisper privacy mode | Shareable beta |

The first concrete steps, in order, are these:

| # | Step | Source to copy from | Done when |
|---|---|---|---|
| 1 | Install a single ESP-IDF version (prefer v6.x) and build xiaozhi for `BOARD_TYPE_WAVESHARE_ESP32_S3_TOUCH_LCD_1_46` unchanged | [xiaozhi Kconfig](https://raw.githubusercontent.com/78/xiaozhi-esp32/main/main/Kconfig.projbuild) | Display, mic and buttons are proven working on your unit |
| 2 | Start a clean IDF project; copy the board's `config.h` pins and the power-hold (GPIO7) and backlight (GPIO5) logic | [board config.h](https://raw.githubusercontent.com/78/xiaozhi-esp32/main/main/boards/waveshare/esp32-s3-touch-lcd-1.46/config.h) | Board boots, holds power and the backlight turns off |
| 3 | Record 16 kHz mono from the I2S mic to SD as rotating 1-minute WAV files with `fsync` on close | [Espressif record_to_sdcard](https://components.espressif.com/components/espressif/esp_board_manager/versions/0.5.11/examples/record_to_sdcard), [Seeed mic example](https://wiki.seeedstudio.com/xiao_esp32s3_sense_mic/) | Clean audio plays back on a laptop |
| 4 | Fit a 500–1000 mAh LiPo, log GPIO8 voltage, measure current with a USB meter in record-only, Wi-Fi and BLE modes | — | The battery estimates above are replaced by real numbers |
| 5 | Record 20–30 minutes of real Hinglish conversation through the pendant (clipped on, across a table, in a noisy café) and A/B test Soniox, Sarvam, AssemblyAI, ElevenLabs, gpt-4o-transcribe and faster-whisper | Section above | Vendor picked on evidence, not marketing |
| 6 | Write the LLM extraction prompt with a JSON schema and run it on those transcripts | Omi extraction fields | Summaries the students would actually reread |
| 7 | In parallel (optional): flash omiGlass firmware onto the XIAO ESP32S3 Sense and pair it with the Omi app | [omiGlass firmware](https://raw.githubusercontent.com/BasedHardware/omi/main/omiGlass/firmware/platformio.ini) | Omi-app compatibility confirmed before porting the protocol |
| 8 | Add the fixed-point Opus encoder (320-sample frames) and the NimBLE GATT audio service on the Waveshare | [omi transport.c](https://raw.githubusercontent.com/BasedHardware/omi/main/omi/firmware/omi/src/lib/core/transport.c), [micro-opus](https://components.espressif.com/components/esphome/micro-opus/versions/0.4.1/examples/encode_benchmark) | Waveshare shows up and transcribes in the Omi app |

For the **mobile apps**, the pragmatic stack is **Flutter with flutter_blue_plus**. A BLE-focused review calls Flutter "a clear edge" over React Native for BLE, flutter_blue_plus is the maintained plugin, and Omi ships the same stack, so its MIT app serves as a reference ([Novel Bits](https://novelbits.io/native-vs-cross-platform-bluetooth-low-energy-mobile-app-platforms/), [Omi App Setup](https://docs.omi.me/doc/developer/AppSetup.md)). Android should come first. Sideloading is free, and a foreground service of type **`connectedDevice`** (not `microphone`, because the phone's own mic is unused) keeps BLE alive on Android 14+. It needs the `FOREGROUND_SERVICE_CONNECTED_DEVICE` permission and Bluetooth permissions ([Android 14 FGS](https://developer.android.com/about/versions/14/changes/fgs-types-required?hl=pl)). Indian OEM skins such as Xiaomi, Realme, Oppo and Vivo aggressively kill background apps, so the app should request a battery-optimization exemption. That is a widely reported community issue, though no source in the notes covers it.

iOS can keep receiving notifications in the background with the `bluetooth-central` mode. State restoration (`CBCentralManagerOptionRestoreIdentifierKey`) relaunches the app after the system kills it for memory, but each wake allows only about 10 s of work, and Apple recommends a session-based UX ([Apple Core Bluetooth](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)). A force-quit likely ends background delivery entirely. The device's SD-first buffering is therefore what makes iOS viable, not a nice-to-have. The team should check whether flutter_blue_plus supports state restoration; if it does not, they will need a small Swift plugin. On-phone Whisper transcription (WhisperKit on iOS, whisper.cpp on Android) works best as an overnight-while-charging privacy mode, not as continuous processing ([WhisperKit paper](https://arxiv.org/html/2507.10860v1)). For app-store review, the team will need a demo mode or video for reviewers who lack the hardware, purpose strings for background Bluetooth, a privacy policy, account deletion, and disclosure labels for audio data.

## Risks to retire early, and four ways to stand apart

| Risk / unknown | Why it matters | How to retire it |
|---|---|---|
| Onboard mic quality (part, SNR unknown) | A single mic muffled by clothing is the dominant factor in transcript quality | Phase 0 pickup test; fallback to an external INMP441 on the 1.27 mm header, or a second mic plus ESP-SR AFE |
| Hinglish STT accuracy | No independent Hindi/Hinglish WER benchmark was found; all claims are vendor marketing | Step 5 A/B test on your own audio |
| Battery life on ESP32-S3 | Estimates of 4–7 h on 500 mAh fall short of the 20 h commercial benchmark | Measure; VAD gating, burst radio, display off, larger cell; nRF port only if it becomes a product |
| ESP32-S3 → phone BLE throughput | No measured S3-to-iPhone/Android figures exist | Log notification throughput at 2M PHY, MTU 247–517 |
| Omi protocol drift | The firmware has a TODO to change the service UUID; docs and app disagree on codec IDs | Pin to codec 21; own your protocol by Phase 2 |
| Data leaving to Omi's cloud | The stock app sends audio to api.omi.me | Use the Omi app only for testing; your own app and backend from Phase 1 |
| SD corruption / power loss | FAT writes interrupted by a dead battery | Segment files, `fsync` on close, a manifest repaired on boot |
| Legal consent | California requires all-party consent and can treat covert recording as a crime ([SF Standard](https://sfstandard.com/2025/08/05/ai-wearables-recording-devices/)). India's DPDP Rules phase in by about May 2027, with consent notices, security safeguards, 72-hour breach reports and erasure ([Mondaq](https://www.mondaq.com/india/data-protection/1708164/digital-personal-data-protection-rules-2025-notified)). India's own recording-consent position was not verified | Visible LED, mute, short retention; get legal review before any public launch |

Differentiation should come from where incumbents are structurally weak, not from feature parity.

**Hindi-English code-switching is the clearest wedge.** Reviewers already report garbled mixed-language transcripts on Limitless, NeoSapien calls the Indian market uncrowded, and Soniox and Sarvam make Hinglish workable on cost ([fast.io](https://www.fast.io/resources/limitless-ai-review-2026.md), [Inc42](https://inc42.com/startups/ai-wearables-neosapien-make-the-most-of-this-wave/)).

**A local-first, no-subscription design answers the rug-pull fear.** Limitless deleted EU and UK users' data within two weeks of its acquisition, and Humane bricked its devices. An open, self-hostable stack with export and bring-your-own-key LLMs speaks directly to that distrust ([9to5Mac](https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/), [Tom's Guide](https://www.tomsguide.com/ai/the-humane-ai-pin-is-officially-dead-and-hp-is-picking-up-humanes-leftovers)).

**Direct Wi-Fi sync is the ESP32's unique trick.** No mainstream pendant uploads straight to a server; the only Wi-Fi claim found, ANYPIN, is unverified. Wi-Fi upload frees the phone from being a constant relay and makes iOS background limits far less painful.

**The display can become a feature instead of a liability.** The screen is off by default, but a tap could show the recording state, a highlight button in the spirit of Plaud's "Press to Highlight", a review of the day's action items, or a "forget the last 5 minutes" control. Plaud's Note Pro already has a screen, which shows users value it ([Plaud](https://www.plaud.ai/blogs/articles/plaud-anniversary)). A wearer-voice-only mode built on speaker profiles adds a privacy story that investors have already funded.

Honest battery claims (continuous-recording hours, not standby) and a recording LED that firmware cannot silently disable cost almost nothing and fix two of the most common complaints in the category.

## Features to build beyond the market (voice only, added 31 Oct)

This section answers a follow-up: no camera for now, voice only on the Waveshare board, with always-on recording, a button that pauses it, and features the market doesn't offer, such as talking to AI agents like Claude. It is a brainstorm ranked by judgment, not by sourced research. Difficulty is an estimate for a two-person team that has already finished Phase 1 (recording, BLE and a basic app).

The Waveshare board has two things most pendants lack: **a speaker** (PCM5101 audio output) and **a round touchscreen**, plus a motion sensor (QMI8658). Those are what make the ideas below possible. Most commercial pendants are a mic and one button, with every interaction happening on the phone. Your pendant can answer back and show things, so that's the advantage to build on. Of the products in this report, only Friend 2.0 has a speaker, and it's built for companionship rather than getting work done.

### One button, a clear set of gestures

Decide the button behaviour first, because every feature hangs off it:

| Gesture | Action | Screen shows |
|---|---|---|
| Nothing (default) | Always-on ambient recording, with silence skipped by voice detection | Thin green ring, recording timer |
| Short press | **Bookmark**: mark the last 60 s as important | Ring flashes, "Saved" |
| Long press (1 s) | **Pause recording** (privacy). Long-press again to resume. Optional auto-resume after 30 min | Ring turns red, "Paused" |
| Hold and speak | **Talk to your agent** (push-to-talk) | Ring turns blue, live "Listening…" |
| Double-tap the case (motion sensor) | Bookmark without finding the button | Same as short press |
| Turn face-down on a table | Pause recording | Screen off |

### Ranked feature list

| # | Feature | What it does | Who already does something like it | Difficulty |
|---|---|---|---|---|
| 1 | **Privacy pause + "forget last 5 min"** | Long-press pauses. A swipe on the screen deletes the last 5 minutes from SD before it ever uploads. A visible ring shows recording state to people around you | Bee has a mute button; deleting recent audio on the device itself is rare | Easy |
| 2 | **Bookmarks ("clip that")** | Short press marks a moment. Summaries put bookmarked moments first, and you can say "what did I bookmark today?" | Some recorders have highlight marks; few feed them into the AI summary | Easy |
| 3 | **Push-to-talk agent with your day as context** | Hold the button and ask: "What did Zoo say about the deadline?" or "Summarise the last meeting." Claude answers on the round screen, and optionally out loud through the speaker. It searches your own transcripts first | Omi, Bee and Plaud have chat inside the phone app. Asking from the pendant and hearing the answer from it is rare | Medium |
| 4 | **Agent actions with on-screen confirm** | "Add a reminder to call Mum at 7", "Put this in my Notion", "Open a GitHub issue for the bug we just discussed", "Message Zoo the summary". Claude calls tools (MCP servers or your own APIs). The screen shows the draft and you tap to confirm before anything is sent | Omi has an app store with integrations; voice-triggered actions confirmed on the device are rare | Medium–hard |
| 5 | **Glance screen** | The round display shows your next open action item, battery, time since last sync and a recording timer, in a few seconds then dark again | Plaud Note Pro has a small status display; a glanceable to-do face is rare | Easy–medium (LVGL) |
| 6 | **Promise tracker** | Catches commitments ("I'll send it tomorrow") from you and from others, and reminds you on the pendant or phone when they come due: "You told Rahul you'd send the slides" | Everyone extracts action items; tracking who promised what and following up later is rare | Medium |
| 7 | **Study mode** (fits you as students) | A "lecture" button on the screen tags a session as a class. You get structured notes, key terms, flashcards and a 5-question quiz, and can ask "explain what the professor said about X" later | Plaud has templates for meetings and lectures; flashcards and quizzes from your own lectures are rare | Easy–medium |
| 8 | **Hinglish-first** | Transcribe mixed Hindi-English well, and let the user pick the language summaries come out in | NeoSapien claims Indian languages; the big players handle code-switching poorly according to reviews | Medium (vendor choice) |
| 9 | **Your memory as an MCP server** | Expose transcripts, memories and to-dos as an MCP server, so Claude Desktop, Claude Code or other agents can ask "what did I discuss today?" from your laptop | Omi already offers an MCP server, so copy its approach rather than calling it new | Medium |
| 10 | **Morning and evening voice briefing** | Press in the morning and the pendant speaks your open promises and today's events; in the evening it reads back what you did | Daily summaries exist in apps; spoken from the device is rare | Easy once #3 works |
| 11 | **Voice rules ("if I say…")** | User-defined triggers: "note to self" goes to Notion, "remind me" goes to the calendar, "idea:" goes to an ideas list | Omi plugins do some of this with webhooks | Medium |
| 12 | **Works without the phone** | At home or on campus Wi-Fi, the pendant uploads straight to your server, so the phone app is optional | Almost no commercial pendant does this | Medium (already in the roadmap) |
| 13 | **Conversation coach** | After a talk or meeting: how much you spoke versus others, filler words, speaking pace, interruptions | Rare in pendants; exists in sales-call software | Medium (server-side) |
| 14 | **"Only my voice" mode** | Keep only the wearer's speech and drop other people's, which helps with consent laws | A funded startup is building this; no shipping product found | Hard (speaker verification) |
| 15 | **Offline wake word** | "Hey pendant" instead of the button, using Espressif's ESP-SR on the chip | Common in smart speakers | Medium; costs battery, so keep the button as the main way in |

### Suggested build order

1. **Button gestures, privacy pause and bookmarks** (#1, #2). Small firmware work, and they make the device trustworthy.
2. **Push-to-talk agent** (#3). This is your signature feature. The pipeline is: the pendant records the question, the phone or server transcribes it, Claude answers using a search over your transcripts, and the answer appears on screen (text first, speech later). Expect an answer in roughly 2–5 seconds; that latency is an estimate, so measure it.
3. **Glance screen** (#5) and **promise tracker** (#6), which give people a reason to look at the pendant every day.
4. **Study mode** (#7), because you are your own first users.
5. **Agent actions** (#4) and **voice rules** (#11), with confirm-on-screen from day one.
6. **Memory MCP server** (#9), **briefings** (#10) and the rest when the core is solid.

### Notes on building the agent part

- Claude has no built-in speech-to-text or speech output, so the agent is a chain: speech-to-text (the same vendor you pick in Phase 0), then Claude, then text-to-speech for spoken answers (for example ElevenLabs, OpenAI or Sarvam for Hindi voices).
- Run the agent on your server, not on the ESP32. The pendant only records, shows text and plays audio. Claude's API supports tool use and connecting to remote MCP servers, which is how actions like Notion or the calendar would plug in.
- Use a small, fast model for quick questions and a stronger one for "plan my week" or long summaries.
- Never let the agent send a message, pay, or delete anything without a tap on the screen. Voice commands get misheard, and the transcript can contain other people's speech that sounds like a command.
- Battery: the speaker and screen are the most power-hungry parts. Default to short text answers on screen and make spoken answers optional.

### What not to promise yet

- **Full on-device transcription.** The ESP32-S3 can do wake words and short command lists (ESP-SR), but not full speech-to-text. That has to happen on the phone or server.
- **Live translation through the speaker.** Latency and the small speaker make this a poor experience on this board.
- **All-day battery with the screen and speaker in use.** Measure first. The earlier estimate of 4–7 hours assumed the screen stays dark.

## Conclusion

The research changes the problem's shape. The hard parts of an AI pendant are no longer firmware or AI plumbing. MIT code already provides a working board layer for this exact Waveshare unit and a phone-compatible audio protocol, and summarization costs fractions of a cent. What remains hard is **acoustics, power and language**: whether one unnamed mic behind a 3D-printed shell can capture a Hinglish conversation across a table well enough for any STT vendor, and whether an ESP32-S3 can do it for a full working day. Both questions can be answered in the first fortnight with an SD card, a USB power meter and a laptop script, before a single line of app code exists. The students should treat that test as the decision gate for everything after it.

Strategically, the Waveshare board is a learning platform, not the product. If the concept holds, the likely end state is the students' own protocol and app, a display-less ESP32-S3 clip (the XIAO is the stepping stone) that keeps Wi-Fi sync as its signature advantage, and a pipeline tuned for Indian languages that commercial incumbents, now owned by Meta and Amazon, have little incentive to prioritise. Building Omi-compatibility first is a cheap hedge: it gives them a working product on day one and an escape hatch if their own app slips, at the cost of a protocol they should replace once they own the data path.
