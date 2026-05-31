#pragma once

namespace lee {

using TimerCallback = void (*)();

void EnsureAppTimer();
void RemoveAppTimer();
void RegisterTimerCallback(TimerCallback cb);
void UnregisterTimerCallback(TimerCallback cb);

}  // namespace lee
