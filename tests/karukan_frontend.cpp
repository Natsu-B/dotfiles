// Exercise the actual Fcitx addon and event loop, with an isolated client.
#include "karukan.h"
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputpanel.h>
#include <cassert>
#include <iostream>

class Client : public fcitx::InputContext {
public:
    explicit Client(fcitx::Instance& instance)
        : InputContext(instance.inputContextManager(), "karukan-regression") {
        created();
        setCapabilityFlags(fcitx::CapabilityFlag::Preedit);
        focusIn();
    }
    ~Client() override { destroy(); }
    const char* frontend() const override { return "regression"; }
    void commitStringImpl(const std::string& value) override { committed += value; }
    void deleteSurroundingTextImpl(int, unsigned int) override {}
    void forwardKeyImpl(const fcitx::ForwardKeyEvent&) override {}
    void updatePreeditImpl() override {
        ++updates;
        if (preserveConvertedPrefix) {
            assert(inputPanel().clientPreedit().toString().starts_with("日本語"));
        }
    }
    std::string committed;
    int updates = 0;
    bool preserveConvertedPrefix = false;
};

int main() {
    // Load no display/IPC addons, so this cannot replace the desktop's Fcitx.
    char program[] = "karukan-frontend-check";
    char disabled[] = "--disable=all";
    char* arguments[] = {program, disabled, nullptr};
    fcitx::Instance instance(2, arguments);
    instance.initialize();
    fcitx::KarukanEngine addon(&instance);
    Client client(instance);
    fcitx::KarukanState state(&addon, &client);
    auto press = [&](fcitx::KeySym key, fcitx::KeyStates modifiers = {}) {
        fcitx::KeyEvent event(&client, fcitx::Key(key, modifiers));
        state.keyEvent(event);
    };
    // Type before the asynchronous model load completes. The frontend timer
    // must later install the model AND rewrite this preedit, with no extra key.
    for (char character : std::string("nihongo")) {
        press(static_cast<fcitx::KeySym>(character));
    }
    assert(client.inputPanel().clientPreedit().toString() == "にほんご");
    bool converted = false;
    bool awaitingExtension = false;
    const auto deadline = fcitx::now(CLOCK_MONOTONIC) + 15000000;
    auto check = instance.eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 10000, 1000,
        [&](fcitx::EventSourceTime* source, uint64_t) {
            if (!awaitingExtension && client.inputPanel().clientPreedit().toString() == "日本語") {
                assert(client.committed.empty());
                // No event-loop turn between these keys: completed new kana
                // must keep the previous conversion while GPU work is pending.
                press(FcitxKey_d);
                assert(client.inputPanel().clientPreedit().toString() == "日本語d");
                press(FcitxKey_e);
                assert(client.inputPanel().clientPreedit().toString() == "日本語で");
                press(FcitxKey_s);
                assert(client.inputPanel().clientPreedit().toString() == "日本語でs");
                press(FcitxKey_u);
                assert(client.inputPanel().clientPreedit().toString() == "日本語です");
                assert(client.committed.empty());
                press(FcitxKey_Return);
                assert(client.committed == "日本語です");
                client.committed.clear();
                std::cout << "PASS: cached conversion + new kana/romaji while pending; current text commits\n";
                state.reset();
                for (char character : std::string("nihongonyuuryoku")) {
                    press(static_cast<fcitx::KeySym>(character));
                }
                assert(client.inputPanel().clientPreedit().toString() == "日本語にゅうりょく");
                client.preserveConvertedPrefix = true;
                awaitingExtension = true;
            }
            if (awaitingExtension && client.inputPanel().clientPreedit().toString() == "日本語入力") {
                converted = true;
                client.preserveConvertedPrefix = false;
                press(FcitxKey_Return);
                assert(client.committed == "日本語入力");
                client.committed.clear();
                std::cout << "PASS: timer replaces appended kana without losing converted prefix\n";
                state.reset();
                for (char character : std::string("hashi")) {
                    press(static_cast<fcitx::KeySym>(character));
                }
                press(FcitxKey_space);
                auto list = [&]() {
                    return dynamic_cast<fcitx::CommonCandidateList*>(
                        client.inputPanel().candidateList().get());
                };
                assert(list());
                const auto first = client.inputPanel().clientPreedit().toString();
                int count = 0;
                int aiCandidates = 0;
                // Rust exposes one page at a time; continue through later pages.
                do {
                    const int index = list()->globalCursorIndex();
                    assert(client.inputPanel().clientPreedit().toString() ==
                           list()->candidateFromAll(index).text().toString());
                    if (client.inputPanel().auxUp().toString().find("AI") != std::string::npos) {
                        ++aiCandidates;
                    }
                    assert(client.committed.empty());
                    assert(++count < 100);
                    press(FcitxKey_space);
                } while (client.inputPanel().clientPreedit().toString() != first);
                assert(aiCandidates >= 2);
                assert(list()->globalCursorIndex() == 0);
                press(FcitxKey_space);
                assert(list()->globalCursorIndex() == 1);
                press(FcitxKey_space, fcitx::KeyState::Shift);
                assert(list()->globalCursorIndex() == 0);
                press(FcitxKey_space);
                const auto selected = client.inputPanel().clientPreedit().toString();
                press(FcitxKey_Return);
                assert(client.committed == selected);
                client.committed.clear();
                std::cout << "PASS: Space cycles " << count << " candidates ("
                          << aiCandidates << " AI), wraps, reverses and commits\n";
                // Reset/destroy the frontend timer while the loop is running.
                // sd-event forbids adding new sources after exit().
                state.reset();
                for (char character : std::string("arigatou")) {
                    press(static_cast<fcitx::KeySym>(character));
                }
                client.focusOut();
                state.reset();
                assert(client.inputPanel().clientPreedit().toString().empty());
                instance.eventLoop().exit();
            } else if (fcitx::now(CLOCK_MONOTONIC) >= deadline) {
                instance.eventLoop().exit();
            } else {
                source->setTime(fcitx::now(CLOCK_MONOTONIC) + 10000);
                source->setOneShot();
            }
            return true;
        });
    check->setOneShot();
    instance.eventLoop().exec();
    assert(converted);
    assert(client.updates > 0);
    // Fcitx commits the current client preedit on focus loss.
    assert(client.committed == "ありがとう");
    std::cout << "PASS: live preedit rewritten by Fcitx timer; focus/reset and timer lifetime\n";
}
