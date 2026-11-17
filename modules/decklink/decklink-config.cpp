// decklink-config: read and pin Blackmagic DeckLink / UltraStudio card settings
// (the ones Desktop Video Setup shows) through the DeckLink SDK.
//
//   decklink-config dump            current settings of every card, as JSON in
//                                   the same shape `apply` reads
//   decklink-config apply <file>    make the cards match <file>
//   decklink-config check <file>    print what apply would change; change nothing
//
// Config shape (keys are model names as the driver reports them):
//
//   {
//     "DeckLink Duo 2": {
//       "profile": "FourSubDevicesHalfDuplex",   // optional
//       "all": { "DefaultVideoOutputMode": "Hp59" },
//       "subDevices": { "0": { "DeviceInformationLabel": "Main" }, ... }
//     }
//   }
//
// Setting names are the SDK's bmdDeckLinkConfig* names without the prefix.
// Integer settings also take a four-character code ("Hp59" = 1080p59.94).
// Only settings named in the file are touched, and only when they differ, so
// anything left out stays however the card already has it.

#include <CoreFoundation/CoreFoundation.h>

#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "DeckLinkAPI.h"

using json = nlohmann::ordered_json;

namespace {

bool dryRun = false;

enum class Kind { Flag, Int, Float, String };

struct Setting {
    const char* name;
    BMDDeckLinkConfigurationID id;
    Kind kind;
};

#define S(n, k) { #n, bmdDeckLinkConfig##n, Kind::k }
const Setting kSettings[] = {
    S(SwapSerialRxTx, Flag),
    S(HDMI3DPackingFormat, Int),
    S(Bypass, Int),
    S(ClockTimingAdjustment, Int),
    S(AnalogAudioConsumerLevels, Flag),
    S(SwapHDMICh3AndCh4OnInput, Flag),
    S(SwapHDMICh3AndCh4OnOutput, Flag),
    S(FieldFlickerRemoval, Flag),
    S(HD1080p24ToHD1080i5994Conversion, Flag),
    S(444SDIVideoOutput, Flag),
    S(BlackVideoOutputDuringCapture, Flag),
    S(LowLatencyVideoOutput, Flag),
    S(DownConversionOnAllAnalogOutput, Flag),
    S(SMPTELevelAOutput, Flag),
    S(Rec2020Output, Flag),
    S(QuadLinkSDIVideoOutputSquareDivisionSplit, Flag),
    S(Output1080pAsPsF, Flag),
    S(VideoOutputConnection, Int),
    S(VideoOutputConversionMode, Int),
    S(AnalogVideoOutputFlags, Int),
    S(ReferenceInputTimingOffset, Int),
    S(VideoOutputIdleOperation, Int),
    S(DefaultVideoOutputMode, Int),
    S(DefaultVideoOutputModeFlags, Int),
    S(SDIOutputLinkConfiguration, Int),
    S(HDMITimecodePacking, Int),
    S(PlaybackGroup, Int),
    S(VideoOutputComponentLumaGain, Float),
    S(VideoOutputComponentChromaBlueGain, Float),
    S(VideoOutputComponentChromaRedGain, Float),
    S(VideoOutputCompositeLumaGain, Float),
    S(VideoOutputCompositeChromaGain, Float),
    S(VideoOutputSVideoLumaGain, Float),
    S(VideoOutputSVideoChromaGain, Float),
    S(VideoInputScanning, Flag),
    S(UseDedicatedLTCInput, Flag),
    S(SDIInput3DPayloadOverride, Flag),
    S(Capture1080pAsPsF, Flag),
    S(VideoInputConnection, Int),
    S(AnalogVideoInputFlags, Int),
    S(VideoInputConversionMode, Int),
    S(32PulldownSequenceInitialTimecodeFrame, Int),
    S(VANCSourceLine1Mapping, Int),
    S(VANCSourceLine2Mapping, Int),
    S(VANCSourceLine3Mapping, Int),
    S(CapturePassThroughMode, Int),
    S(CaptureGroup, Int),
    S(VideoInputComponentLumaGain, Float),
    S(VideoInputComponentChromaBlueGain, Float),
    S(VideoInputComponentChromaRedGain, Float),
    S(VideoInputCompositeLumaGain, Float),
    S(VideoInputCompositeChromaGain, Float),
    S(VideoInputSVideoLumaGain, Float),
    S(VideoInputSVideoChromaGain, Float),
    S(InternalKeyingAncillaryDataSource, Int),
    S(MicrophonePhantomPower, Flag),
    S(AudioInputConnection, Int),
    S(AnalogAudioInputScaleChannel1, Float),
    S(AnalogAudioInputScaleChannel2, Float),
    S(AnalogAudioInputScaleChannel3, Float),
    S(AnalogAudioInputScaleChannel4, Float),
    S(DigitalAudioInputScale, Float),
    S(MicrophoneInputGain, Float),
    S(AudioOutputAESAnalogSwitch, Int),
    S(AnalogAudioOutputScaleChannel1, Float),
    S(AnalogAudioOutputScaleChannel2, Float),
    S(AnalogAudioOutputScaleChannel3, Float),
    S(AnalogAudioOutputScaleChannel4, Float),
    S(DigitalAudioOutputScale, Float),
    S(HeadphoneVolume, Float),
    S(DeviceInformationLabel, String),
    S(DeviceInformationSerialNumber, String),
    S(DeviceInformationCompany, String),
    S(DeviceInformationPhone, String),
    S(DeviceInformationEmail, String),
    S(DeviceInformationDate, String),
    S(DeckControlConnection, Int),
};
#undef S

const std::map<std::string, BMDProfileID> kProfiles = {
    { "OneSubDeviceFullDuplex", bmdProfileOneSubDeviceFullDuplex },
    { "OneSubDeviceHalfDuplex", bmdProfileOneSubDeviceHalfDuplex },
    { "TwoSubDevicesFullDuplex", bmdProfileTwoSubDevicesFullDuplex },
    { "TwoSubDevicesHalfDuplex", bmdProfileTwoSubDevicesHalfDuplex },
    { "FourSubDevicesHalfDuplex", bmdProfileFourSubDevicesHalfDuplex },
};

const Setting* findSetting(const std::string& name) {
    for (const auto& s : kSettings)
        if (name == s.name) return &s;
    return nullptr;
}

std::string profileName(int64_t id) {
    for (const auto& [name, pid] : kProfiles)
        if (pid == id) return name;
    return std::to_string(id);
}

std::string toStd(CFStringRef s) {
    if (!s) return "";
    CFIndex len = CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), kCFStringEncodingUTF8) + 1;
    std::string out(len, '\0');
    if (!CFStringGetCString(s, out.data(), len, kCFStringEncodingUTF8)) return "";
    out.resize(strlen(out.c_str()));
    return out;
}

// Integers that are four printable characters (display modes, most enums)
// read better as their code: "Hp59", not 1215312697.
json intValue(int64_t v) {
    if (v >= 0x20202020 && v <= 0x7e7e7e7e) {
        char c[5] = { char(v >> 24), char(v >> 16), char(v >> 8), char(v), 0 };
        bool printable = true;
        for (int i = 0; i < 4; i++) printable &= c[i] >= 0x20 && c[i] <= 0x7e;
        if (printable) return std::string(c);
    }
    return v;
}

bool parseInt(const json& v, int64_t* out) {
    if (v.is_number_integer()) { *out = v.get<int64_t>(); return true; }
    if (v.is_string() && v.get<std::string>().size() == 4) {
        auto s = v.get<std::string>();
        *out = (int64_t(uint8_t(s[0])) << 24) | (uint8_t(s[1]) << 16) | (uint8_t(s[2]) << 8) | uint8_t(s[3]);
        return true;
    }
    return false;
}

struct Device {
    IDeckLink* deckLink;
    std::string model;
    std::string displayName;
    int64_t subDevice = 0;
    int64_t persistentId = -1;
};

std::vector<Device> enumerate() {
    std::vector<Device> out;
    IDeckLinkIterator* it = CreateDeckLinkIteratorInstance();
    if (!it) return out;
    IDeckLink* dl = nullptr;
    while (it->Next(&dl) == S_OK) {
        Device d { dl };
        CFStringRef s = nullptr;
        if (dl->GetModelName(&s) == S_OK) { d.model = toStd(s); CFRelease(s); }
        if (dl->GetDisplayName(&s) == S_OK) { d.displayName = toStd(s); CFRelease(s); }
        IDeckLinkProfileAttributes* attr = nullptr;
        if (dl->QueryInterface(IID_IDeckLinkProfileAttributes, (void**)&attr) == S_OK) {
            attr->GetInt(BMDDeckLinkSubDeviceIndex, &d.subDevice);
            attr->GetInt(BMDDeckLinkPersistentID, &d.persistentId);
            attr->Release();
        }
        out.push_back(d);
    }
    it->Release();
    return out;
}

void release(std::vector<Device>& devices) {
    for (auto& d : devices) d.deckLink->Release();
    devices.clear();
}

int64_t activeProfile(IDeckLink* dl) {
    int64_t id = 0;
    IDeckLinkProfileAttributes* attr = nullptr;
    if (dl->QueryInterface(IID_IDeckLinkProfileAttributes, (void**)&attr) == S_OK) {
        attr->GetInt(BMDDeckLinkProfileID, &id);
        attr->Release();
    }
    return id;
}

json readSettings(IDeckLinkConfiguration* cfg) {
    json out = json::object();
    for (const auto& s : kSettings) {
        switch (s.kind) {
        case Kind::Flag: { bool v; if (cfg->GetFlag(s.id, &v) == S_OK) out[s.name] = v; break; }
        case Kind::Int: { int64_t v; if (cfg->GetInt(s.id, &v) == S_OK) out[s.name] = intValue(v); break; }
        case Kind::Float: { double v; if (cfg->GetFloat(s.id, &v) == S_OK) out[s.name] = v; break; }
        case Kind::String: {
            CFStringRef v = nullptr;
            if (cfg->GetString(s.id, &v) == S_OK) { out[s.name] = toStd(v); if (v) CFRelease(v); }
            break;
        }
        }
    }
    return out;
}

int dump() {
    auto devices = enumerate();
    json out = json::object();
    for (auto& d : devices) {
        json& card = out[d.model];
        if (!card.contains("profile")) {
            card["profile"] = profileName(activeProfile(d.deckLink));
            IDeckLinkProfileManager* pm = nullptr;
            if (d.deckLink->QueryInterface(IID_IDeckLinkProfileManager, (void**)&pm) == S_OK) {
                json avail = json::array();
                IDeckLinkProfileIterator* pit = nullptr;
                if (pm->GetProfiles(&pit) == S_OK) {
                    IDeckLinkProfile* p = nullptr;
                    while (pit->Next(&p) == S_OK) {
                        IDeckLinkProfileAttributes* pa = nullptr;
                        if (p->QueryInterface(IID_IDeckLinkProfileAttributes, (void**)&pa) == S_OK) {
                            int64_t id = 0;
                            pa->GetInt(BMDDeckLinkProfileID, &id);
                            avail.push_back(profileName(id));
                            pa->Release();
                        }
                        p->Release();
                    }
                    pit->Release();
                }
                card["_availableProfiles"] = avail;
                pm->Release();
            }
            card["subDevices"] = json::object();
        }
        json sub = { { "_displayName", d.displayName }, { "_persistentId", d.persistentId } };
        IDeckLinkConfiguration* cfg = nullptr;
        if (d.deckLink->QueryInterface(IID_IDeckLinkConfiguration, (void**)&cfg) == S_OK) {
            sub.update(readSettings(cfg));
            cfg->Release();
        }
        card["subDevices"][std::to_string(d.subDevice)] = sub;
    }
    release(devices);
    std::cout << out.dump(2) << std::endl;
    return 0;
}

class ProfileWaiter : public IDeckLinkProfileCallback {
public:
    std::mutex m;
    std::condition_variable cv;
    bool activated = false;

    HRESULT ProfileChanging(IDeckLinkProfile*, bool streamsWillBeForcedToStop) override {
        if (streamsWillBeForcedToStop)
            std::cerr << "warning: an app is using the card; its streams stop for the profile change" << std::endl;
        return S_OK;
    }
    HRESULT ProfileActivated(IDeckLinkProfile*) override {
        std::lock_guard<std::mutex> l(m);
        activated = true;
        cv.notify_all();
        return S_OK;
    }
    HRESULT QueryInterface(REFIID, LPVOID* ppv) override { *ppv = nullptr; return E_NOINTERFACE; }
    ULONG AddRef() override { return 1; }
    ULONG Release() override { return 1; }
};

// Returns false on error. One SetActive changes every sub-device of the card.
bool applyProfile(Device& d, const std::string& want) {
    auto pid = kProfiles.find(want);
    if (pid == kProfiles.end()) {
        std::cerr << "error: unknown profile " << want << std::endl;
        return false;
    }
    if (activeProfile(d.deckLink) == pid->second) return true;

    if (dryRun) {
        std::cout << d.model << ": profile " << profileName(activeProfile(d.deckLink)) << " -> " << want << " (not applied)" << std::endl;
        return true;
    }

    IDeckLinkProfileManager* pm = nullptr;
    if (d.deckLink->QueryInterface(IID_IDeckLinkProfileManager, (void**)&pm) != S_OK) {
        std::cerr << "error: " << d.model << " has only one profile; can't set " << want << std::endl;
        return false;
    }
    IDeckLinkProfile* p = nullptr;
    bool ok = false;
    if (pm->GetProfile(pid->second, &p) != S_OK) {
        std::cerr << "error: " << d.model << " doesn't offer profile " << want << std::endl;
    } else {
        ProfileWaiter waiter;
        pm->SetCallback(&waiter);
        std::cout << d.model << ": profile " << profileName(activeProfile(d.deckLink)) << " -> " << want << std::endl;
        if (p->SetActive() != S_OK) {
            std::cerr << "error: activating " << want << " failed" << std::endl;
        } else {
            std::unique_lock<std::mutex> l(waiter.m);
            ok = waiter.cv.wait_for(l, std::chrono::seconds(20), [&] { return waiter.activated; });
            if (!ok) std::cerr << "error: profile change didn't finish in time" << std::endl;
        }
        pm->SetCallback(nullptr);
        p->Release();
    }
    pm->Release();
    return ok;
}

bool sameValue(const Setting& s, IDeckLinkConfiguration* cfg, const json& want, bool* readOk) {
    *readOk = true;
    switch (s.kind) {
    case Kind::Flag: { bool v; if (cfg->GetFlag(s.id, &v) != S_OK) break; return v == want.get<bool>(); }
    case Kind::Int: { int64_t v, w; if (cfg->GetInt(s.id, &v) != S_OK) break; parseInt(want, &w); return v == w; }
    case Kind::Float: { double v; if (cfg->GetFloat(s.id, &v) != S_OK) break; return v == want.get<double>(); }
    case Kind::String: {
        CFStringRef v = nullptr;
        if (cfg->GetString(s.id, &v) != S_OK) break;
        bool same = toStd(v) == want.get<std::string>();
        if (v) CFRelease(v);
        return same;
    }
    }
    *readOk = false;
    return false;
}

bool validValue(const Setting& s, const json& v) {
    switch (s.kind) {
    case Kind::Flag: return v.is_boolean();
    case Kind::Int: { int64_t i; return parseInt(v, &i); }
    case Kind::Float: return v.is_number();
    case Kind::String: return v.is_string();
    }
    return false;
}

HRESULT writeValue(const Setting& s, IDeckLinkConfiguration* cfg, const json& v) {
    switch (s.kind) {
    case Kind::Flag: return cfg->SetFlag(s.id, v.get<bool>());
    case Kind::Int: { int64_t i; parseInt(v, &i); return cfg->SetInt(s.id, i); }
    case Kind::Float: return cfg->SetFloat(s.id, v.get<double>());
    case Kind::String: {
        CFStringRef str = CFStringCreateWithCString(kCFAllocatorDefault, v.get<std::string>().c_str(), kCFStringEncodingUTF8);
        HRESULT r = cfg->SetString(s.id, str);
        CFRelease(str);
        return r;
    }
    }
    return E_FAIL;
}

// Returns the number of errors.
int applySettings(Device& d, const json& settings) {
    IDeckLinkConfiguration* cfg = nullptr;
    if (d.deckLink->QueryInterface(IID_IDeckLinkConfiguration, (void**)&cfg) != S_OK) {
        std::cerr << "error: " << d.displayName << " has no configuration interface" << std::endl;
        return 1;
    }
    int errors = 0, changed = 0;
    for (const auto& [name, value] : settings.items()) {
        if (!name.empty() && name[0] == '_') continue; // informational, from dump
        const Setting* s = findSetting(name);
        if (!s) { std::cerr << "error: unknown setting " << name << std::endl; errors++; continue; }
        if (!validValue(*s, value)) {
            std::cerr << "error: " << name << ": wrong type for " << value.dump() << std::endl;
            errors++;
            continue;
        }
        bool readOk;
        if (sameValue(*s, cfg, value, &readOk)) continue;
        if (!readOk) {
            std::cerr << "warning: " << d.displayName << " doesn't support " << name << "; skipped" << std::endl;
            continue;
        }
        if (dryRun) {
            std::cout << d.displayName << ": " << name << " -> " << value.dump() << " (not applied)" << std::endl;
        } else if (writeValue(*s, cfg, value) == S_OK) {
            std::cout << d.displayName << ": " << name << " = " << value.dump() << std::endl;
            changed++;
        } else {
            std::cerr << "error: " << d.displayName << ": setting " << name << " to " << value.dump() << " failed" << std::endl;
            errors++;
        }
    }
    if (changed && cfg->WriteConfigurationToPreferences() != S_OK) {
        std::cerr << "error: " << d.displayName << ": saving settings failed (needs root)" << std::endl;
        errors++;
    }
    cfg->Release();
    return errors;
}

int apply(const char* path) {
    json want;
    try {
        std::ifstream f(path);
        want = json::parse(f);
    } catch (const std::exception& e) {
        std::cerr << "error: reading " << path << ": " << e.what() << std::endl;
        return 1;
    }

    auto devices = enumerate();
    if (devices.empty()) {
        std::cout << "no DeckLink devices found (driver not loaded yet?); nothing to do" << std::endl;
        return 0;
    }

    int errors = 0;

    // Profiles first: they decide which sub-devices exist.
    bool profileChanged = false;
    for (auto& d : devices) {
        if (!want.contains(d.model) || !want[d.model].contains("profile")) continue;
        std::string target = want[d.model]["profile"];
        int64_t before = activeProfile(d.deckLink);
        if (!applyProfile(d, target)) errors++;
        else if (activeProfile(d.deckLink) != before) profileChanged = true;
    }
    if (profileChanged) {
        release(devices);
        devices = enumerate();
    }

    std::map<std::string, bool> seen;
    for (auto& d : devices) {
        seen[d.model] = true;
        if (!want.contains(d.model)) continue;
        const json& card = want[d.model];
        json merged = card.value("all", json::object());
        if (card.contains("subDevices")) {
            auto key = std::to_string(d.subDevice);
            if (card["subDevices"].contains(key)) merged.update(card["subDevices"][key]);
        }
        errors += applySettings(d, merged);
    }
    release(devices);

    for (const auto& [model, _] : want.items())
        if (!seen.count(model))
            std::cout << "note: no " << model << " in this Mac; its settings were skipped" << std::endl;

    return errors ? 1 : 0;
}

} // namespace

int main(int argc, char** argv) {
    std::string cmd = argc > 1 ? argv[1] : "";
    if (cmd == "dump" && argc == 2) return dump();
    if (cmd == "apply" && argc == 3) return apply(argv[2]);
    if (cmd == "check" && argc == 3) { dryRun = true; return apply(argv[2]); }
    std::cerr << "usage: decklink-config dump\n"
                 "       decklink-config apply <config.json>\n"
                 "       decklink-config check <config.json>" << std::endl;
    return 2;
}
