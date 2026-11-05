# Omi features, in build order

Source: github.com/BasedHardware/omi (app, backend, firmware, docs), read 2026-11-01.
License is MIT, so we may reuse their code as long as we keep their copyright notice. Mostly we copy ideas.
Our rule: everything runs on the phone/Mac. Cloud only if the user turns it on.

## Already have ✅
- Record on pendant, button to start/stop
- Save on the pendant offline, sync to phone later
- Fast BLE + Opus live streaming (Omi uses the same codec)
- Battery on the pendant screen
- Live transcription on the phone (Omi: cloud STT. Us: SpeechAnalyzer)
- Live transcript while recording + Start live button in app (2026-11-02: LiveTranscriber.swift, firmware "R:1"/"R:0")
- Summary + action items (Omi: cloud LLM. Us: Foundation Models / Qwen3)

## To build, one at a time
1. ✅ (2026-11-02, app: Splitter.swift) **Auto-split conversations.** Omi: 2 min of silence starts a new one; silence-only clips are dropped. Us: same rule, in the app.
2. ✅ (2026-11-02, app) **Title, short overview, category** per conversation. Omi: cloud LLM. Us: on-device LLM.
3. **Conversation list + search.** (DONE 2026-11-02, on-device) Omi: timeline + vector search in cloud. Us: local DB + on-device embeddings.
4. ✅ (2026-11-03, To-dos tab + Reminders) **Real to-do list.** Omi: checkable action items, calendar events pulled out. Us: local list, push to Apple Reminders/Calendar.
5. **Memories** (short facts about you, linked to the source). Omi: cloud extraction, you edit/delete. Us: same, stored on phone.
6. **Chat with your life** ("what did I promise Sam Tuesday?") with links to sources. Omi: cloud agent with search tools. Us: local search + local LLM; cloud LLM opt-in.
7. ✅ (2026-11-02, app, FluidAudio Sortformer; labels only, no naming yet) **Who's speaking.** Omi: diarization, voice profile for you, name other people → People page. Us: on-device speaker model.
8. **Daily recap** notification each evening. Us: local scheduled job.
9. ✅ (2026-11-03) **Language + custom words** (Hinglish, names). Omi: language setting + custom vocabulary. Us: SpeechAnalyzer locale + word hints.
10. ✅ (2026-11-03, phone recording) **Phone-only mode** (record without pendant) + "Transcribe later".
11. **Button gestures**: long press = privacy pause, double tap = bookmark. Omi: button + haptic. Us: button + screen.
12. **Ask by voice, hear the answer** on the pendant speaker. Omi: chat + TTS. Us: on-device TTS sent back over BLE.
13. **Battery saver**: only record when someone talks. Omi: mic hardware wake-on-sound. Us: ESP32 voice detection.
14. **Firmware updates from the app.** Omi: BLE DFU. Us: ESP-IDF OTA over BLE.
15. **Live tips during a talk** (Omi "advice"/proactive notifications). Us: local LLM on the live transcript.
16. **Goals** you set, tracked from your conversations.
17. **Edit tools**: folders, merge/split, fix transcript, star.
18. ✅ (2026-11-03, text/PDF/audio) **Share / export** a conversation. Omi: public web link. Us: share sheet (text/PDF), no hosting.
19. **Export all data / delete all.**
20. **Integrations**: calendar, Reminders, Todoist/Notion, Apple Health. Opt-in per app.
21. **Custom "apps"**: your own prompt run on every conversation, webhooks. Us: local prompts; webhooks opt-in.
22. **Let Claude/other AIs read your memory.** Omi: MCP server + API. Us: local MCP on the Mac, opt-in.
23. (Siri shortcuts done 2026-11-03; widgets not yet) **Home widgets, Siri shortcuts.**
24. **Mac app** that captures meetings/screen, synced with the phone over local Wi-Fi.
25. **Fun extras**: yearly "Wrapped", knowledge graph, persona chatbot.
26. **Android app.**

Skipped for now: omiGlass camera (no camera), phone-call recording (hard on iOS), paid plans/app store.

## Research 2026-11-02 (Omi repo PRODUCT.md + docs, FluidAudio)
Omi's rule: Capture → Understand → Remember → Retrieve → Act. "Trust over cleverness": never silently lose data.
Recommended next, in order:
1. ✅ (2026-11-02, People.swift) **Your voice + named people.** Omi tags "you" via an enrolled speech profile and remembers named voices across conversations (diarization alone is weak, even for Omi). Us: 20 s voice enrollment, FluidAudio speaker embeddings (WeSpeaker) matched by cosine; "Person 2 is Sam" saves Sam's voice locally.
2. ✅ (2026-11-02) **Never delete silently.** Omi keeps short/silent fragments under "Show discarded". Us: move dropped clips to a Discarded list instead of deleting.
3. **Search + list (#3).** Local SQLite/FTS + Apple NaturalLanguage embeddings.
4. **Memories + daily recap (#5, #8).**
5. **Wi-Fi bulk sync** for long offline recordings (Plaud "Wi-Fi fast transfer"; ESP32-S3 has Wi-Fi).
Done 2026-11-02: live join/catch-up (firmware 'J' + "O:" range read).
