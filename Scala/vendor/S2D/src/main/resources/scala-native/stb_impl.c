#define STB_IMAGE_IMPLEMENTATION
/* WhaleKart: Scala Native passes UTF-8 paths, including Windows usernames. */
#define STBI_WINDOWS_UTF8
#if __has_include(<stb/stb_image.h>)
#include <stb/stb_image.h>
#else
/* WhaleKart portability: vcpkg installs stb headers directly in include/. */
#include <stb_image.h>
#endif

#define STB_TRUETYPE_IMPLEMENTATION
#if __has_include(<stb/stb_truetype.h>)
#include <stb/stb_truetype.h>
#else
#include <stb_truetype.h>
#endif
