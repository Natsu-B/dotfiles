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
    void updatePreeditImpl() override { ++updates; }
    std::string committed;
    int updates = 0;
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
    // Type before the asynchronous model load completes. The frontend timer
    // must later install the model AND rewrite this preedit, with no extra key.
    for (char character : std::string("nihongo")) {
        fcitx::KeyEvent event(&client, fcitx::Key(static_cast<fcitx::KeySym>(character)));
        state.keyEvent(event);
    }
    assert(client.inputPanel().clientPreedit().toString() == "にほんご");
    bool converted = false;
    const auto deadline = fcitx::now(CLOCK_MONOTONIC) + 15000000;
    auto check = instance.eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 10000, 1000,
        [&](fcitx::EventSourceTime* source, uint64_t) {
            if (client.inputPanel().clientPreedit().toString() == "日本語") {
                converted = true;
                assert(client.committed.empty());
                // Reset/destroy the frontend timer while the loop is running.
                // sd-event forbids adding new sources after exit().
                state.reset();
                for (char character : std::string("arigatou")) {
                    fcitx::KeyEvent event(&client, fcitx::Key(static_cast<fcitx::KeySym>(character)));
                    state.keyEvent(event);
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
