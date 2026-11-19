/* Run against SDL_mixer's real decoders and dummy audio device, without a GPU.
 * Usage from Scala: cc -std=c11 tools/test_audio.c $(pkg-config --cflags --libs
 * sdl2 SDL2_mixer) -o target/test-audio && target/test-audio target/assets
 */
#include "../native/src/main/resources/scala-native/whaley_audio.c"
#include <math.h>
#include <stdio.h>
#include <stdatomic.h>

static atomic_int rendered_samples;

static void count_samples(void *unused, Uint8 *stream, int length) {
    (void)unused;
    const Sint16 *samples = (const Sint16 *)stream;
    for (int index = 0; index < length / (int)sizeof(*samples); ++index) {
        if (samples[index] != 0) {
            atomic_fetch_add(&rendered_samples, 1);
            break;
        }
    }
}

static void require_audio(int passed, const char *message) {
    if (!passed) {
        fprintf(stderr, "Audio check failed: %s (%s; %s)\n", message,
                whaley_audio_error(), SDL_GetError());
        exit(1);
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <asset directory>\n", argv[0]);
        return 2;
    }
    const char *effects[] = {"knock.mp3", "pause01.wav", "jump01.wav",
                            "bounce01.wav", "coin01.wav", "flame01.wav",
                            "goal01.wav", "bg01.mp3"};
    char path[4096];
    SDL_setenv("SDL_AUDIODRIVER", "dummy", 1);
    WhaleyAudio *audio = whaley_audio_open(8);
    require_audio(audio != NULL, "open dummy output with MP3 decoding");
    Mix_SetPostMix(count_samples, NULL);
    for (int index = 0; index < 8; ++index) {
        SDL_snprintf(path, sizeof(path), "%s/%s", argv[1], effects[index]);
        require_audio(whaley_audio_load_effect(audio, index, path, index == 0 ? 64 : 128) == 0,
                      effects[index]);
        atomic_store(&rendered_samples, 0);
        require_audio(whaley_audio_play(audio, index, 1) == 0, "play original effect");
        SDL_Delay(150);
        require_audio(atomic_load(&rendered_samples) > 0, "original effect produces PCM samples");
        whaley_audio_stop_effects(audio);
    }
    require_audio(Mix_VolumeChunk(audio->effects[0], -1) == 64, "original half-gain knock");

    require_audio(whaley_audio_play(audio, 4, 0) == 0 &&
                  whaley_audio_play(audio, 4, 0) == 0, "overlapping coin playback");
    require_audio(Mix_Playing(-1) == 2, "coin uses independent voices");
    whaley_audio_stop_effects(audio);
    require_audio(Mix_Playing(-1) == 0, "scene teardown stops every effect");

    require_audio(whaley_audio_play(audio, 2, 1) == 0 &&
                  whaley_audio_play(audio, 2, 1) == 0, "guarded jump playback");
    require_audio(Mix_Playing(-1) == 1, "guarded source does not overlap itself");
    whaley_audio_stop_effects(audio);

    for (int track = 0; track < 2; ++track) {
        SDL_snprintf(path, sizeof(path), "%s/%s.mp3", argv[1], track == 0 ? "A" : "B");
        require_audio(whaley_audio_music(audio, path) == 0, "start original menu track");
        SDL_Delay(150);
        whaley_audio_pause_music(audio);
        double paused = Mix_GetMusicPosition(audio->music);
        require_audio(Mix_PausedMusic() && paused > 0, "music pauses after progressing");
        SDL_Delay(100);
        require_audio(fabs(Mix_GetMusicPosition(audio->music) - paused) < 0.03,
                      "music position stays fixed while paused");
        require_audio(whaley_audio_music(audio, path) == 0, "resume retained music");
        SDL_Delay(100);
        require_audio(!Mix_PausedMusic() && Mix_GetMusicPosition(audio->music) > paused,
                      "music resumes from retained position");
    }
    require_audio(Mix_SetMusicPosition(Mix_MusicDuration(audio->music) - 0.1) == 0,
                  "seek near end of original B track");
    SDL_Delay(500);
    require_audio(!Mix_PlayingMusic(), "menu track finishes without looping");
    require_audio(whaley_audio_music(audio, path) == 0 && !Mix_PlayingMusic(),
                  "return to gallery does not restart a naturally finished track");
    Mix_SetPostMix(NULL, NULL);
    whaley_audio_close(audio);
    puts("Original audio passed: all 10 decoders, PCM output, overlap, gain, pause/resume, completion and cleanup.");
    return 0;
}
