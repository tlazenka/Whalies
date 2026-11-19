/* Whaley owns this small SDL_mixer 2 boundary. SDL_mixer allocates all opaque
 * decoder objects; Scala never guesses their sizes or enters audio callbacks.
 */
#if __has_include(<SDL2/SDL.h>) && __has_include(<SDL2/SDL_mixer.h>)
#include <SDL2/SDL.h>
#include <SDL2/SDL_mixer.h>
#elif __has_include(<SDL.h>) && __has_include(<SDL_mixer.h>)
#include <SDL.h>
#include <SDL_mixer.h>
#else
#error "SDL2 and SDL2_mixer headers not found. Install sdl2-compat and sdl2_mixer; check sdl2-config --cflags."
#endif
#include <stdlib.h>
#include <string.h>

typedef struct WhaleyAudio {
    Mix_Chunk **effects;
    int effect_count;
    int next_voice;
    int device_open;
    Mix_Music *music;
    char *music_path;
    int music_started;
} WhaleyAudio;

static char whaley_error[512];

static int fail_audio(const char *operation) {
    SDL_snprintf(whaley_error, sizeof(whaley_error), "%s: %s", operation, SDL_GetError());
    return -1;
}

const char *whaley_audio_error(void) { return whaley_error; }

void whaley_audio_close(WhaleyAudio *audio) {
    if (!audio) return;
    if (audio->device_open) {
        Mix_HaltChannel(-1);
        Mix_HaltMusic();
    }
    for (int index = 0; index < audio->effect_count; ++index)
        if (audio->effects[index]) Mix_FreeChunk(audio->effects[index]);
    if (audio->music) Mix_FreeMusic(audio->music);
    SDL_free(audio->music_path);
    free(audio->effects);
    if (audio->device_open) Mix_CloseAudio();
    Mix_Quit();
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    free(audio);
}

WhaleyAudio *whaley_audio_open(int effect_count) {
    whaley_error[0] = '\0';
    if (effect_count < 1 || effect_count > 16) {
        SDL_SetError("Effect count must be between 1 and 16");
        fail_audio("Initializing audio");
        return NULL;
    }
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        fail_audio("Initializing SDL audio");
        return NULL;
    }
    WhaleyAudio *audio = calloc(1, sizeof(*audio));
    if (!audio) {
        SDL_SetError("Out of memory");
        fail_audio("Allocating audio owner");
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        return NULL;
    }
    audio->effects = calloc((size_t)effect_count, sizeof(*audio->effects));
    if (!audio->effects) {
        SDL_SetError("Out of memory");
        fail_audio("Allocating effect slots");
        whaley_audio_close(audio);
        return NULL;
    }
    audio->effect_count = effect_count;
    audio->next_voice = effect_count;
    if ((Mix_Init(MIX_INIT_MP3) & MIX_INIT_MP3) != MIX_INIT_MP3) {
        fail_audio("Loading the SDL_mixer MP3 decoder");
        whaley_audio_close(audio);
        return NULL;
    }
    if (Mix_OpenAudio(44100, AUDIO_S16SYS, 2, 1024) != 0) {
        fail_audio("Opening the audio device");
        whaley_audio_close(audio);
        return NULL;
    }
    audio->device_open = 1;
    if (Mix_AllocateChannels(32) != 32) {
        SDL_SetError("Could not allocate 32 mixer channels");
        fail_audio("Allocating effect voices");
        whaley_audio_close(audio);
        return NULL;
    }
    /* The original guarded sources have one dedicated channel each. Other
     * effects use a bounded voice pool so coin/knock/pause sounds can overlap.
     */
    Mix_ReserveChannels(effect_count);
    return audio;
}

int whaley_audio_load_effect(WhaleyAudio *audio, int cue, const char *path, int volume) {
    if (!audio || cue < 0 || cue >= audio->effect_count) return -1;
    Mix_Chunk *effect = Mix_LoadWAV(path);
    if (!effect) return fail_audio(path);
    if (audio->effects[cue]) Mix_FreeChunk(audio->effects[cue]);
    audio->effects[cue] = effect;
    Mix_VolumeChunk(effect, volume);
    return 0;
}

int whaley_audio_play(WhaleyAudio *audio, int cue, int only_when_idle) {
    if (!audio || cue < 0 || cue >= audio->effect_count || !audio->effects[cue]) return -1;
    int channel;
    if (only_when_idle) {
        channel = cue;
        if (Mix_Playing(channel)) return 0;
    } else {
        channel = audio->next_voice++;
        if (audio->next_voice >= 32) audio->next_voice = audio->effect_count;
    }
    Mix_Volume(channel, MIX_MAX_VOLUME);
    if (Mix_PlayChannel(channel, audio->effects[cue], 0) < 0) return fail_audio("Playing effect");
    return 0;
}

int whaley_audio_music(WhaleyAudio *audio, const char *path) {
    if (!audio) return -1;
    if (!audio->music_path || strcmp(audio->music_path, path) != 0) {
        Mix_Music *music = Mix_LoadMUS(path);
        if (!music) return fail_audio(path);
        char *name = SDL_strdup(path);
        if (!name) {
            Mix_FreeMusic(music);
            SDL_SetError("Out of memory");
            return fail_audio("Saving music path");
        }
        Mix_HaltMusic();
        if (audio->music) Mix_FreeMusic(audio->music);
        SDL_free(audio->music_path);
        audio->music = music;
        audio->music_path = name;
        audio->music_started = 0;
    }
    if (Mix_PausedMusic()) Mix_ResumeMusic();
    else if (!audio->music_started) {
        /* Cocos2d uses loop:NO. A naturally completed track is not restarted
         * every time a frame or a return to the menu asks for the same track.
         */
        if (Mix_PlayMusic(audio->music, 0) < 0) return fail_audio("Playing menu music");
        audio->music_started = 1;
    }
    return 0;
}

void whaley_audio_pause_music(WhaleyAudio *audio) {
    if (audio && audio->music) Mix_PauseMusic();
}

void whaley_audio_stop_effects(WhaleyAudio *audio) {
    if (audio && audio->device_open) Mix_HaltChannel(-1);
}
