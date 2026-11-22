/*
 * MoonPixel core, as a C library (moonpixel.dll / libMoonPixelBridge.so / .dylib).
 *
 * The whole game lives in the core (the world, its nations, its people, their models); a front end draws it.
 * Unreal calls these from C++ (the MoonPixel plugin). Everything is single-threaded: call from one thread.
 *
 * Space (the core's): 1 unit = one tile; x east, y up, z south; right-handed. A person is about 0.9 tiles tall.
 * Unreal (left-handed, z up, centimetres): UE.X = x * S, UE.Y = z * S, UE.Z = y * S for a scale S (cm per tile),
 * and every triangle's last two indices swapped (the swap of y and z turns the handedness over).
 * Texture coordinates: v counted from the top of the picture (glTF's and Unreal's convention).
 */
#ifndef MOONPIXEL_H
#define MOONPIXEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MPWorld MPWorld;   /* a world and its society */
typedef struct MPMesh MPMesh;     /* a mesh handed out by the core */

/* The library's version ("3.4.0") and the layout version of these structures (bumped when they change). */
const char *mp_version(void);
int32_t mp_abi(void);

/* A new world from a seed, with `villages` villages of `per` people each round the origin. */
MPWorld *mp_world_create(int64_t seed, int32_t villages, int32_t per);
void mp_world_destroy(MPWorld *w);
/* Run the world on by `seconds` of game time (in steps of at most 0.5 s). */
void mp_world_tick(MPWorld *w, double seconds);
double mp_world_time(const MPWorld *w);
int32_t mp_world_population(const MPWorld *w);

/* A person to draw. Colours are 0xRRGGBB. Positions in tiles. */
typedef struct MPPerson {
    int32_t id;
    float x, z;               /* where (tiles) */
    float facing_x, facing_z; /* the way they face */
    int32_t flags;            /* MP_MOVING | MP_SLEEPING | MP_WORKING | MP_FEMALE | MP_CHILD | MP_ELDER */
    uint32_t skin, hair, shirt, pants, shoes;
    int32_t style;            /* hair style */
    char model[24];           /* a character model's key ("knight"...) or empty */
    char held[16];            /* what the hand holds ("sword", "axe"...) or empty */
} MPPerson;
enum { MP_MOVING = 1, MP_SLEEPING = 2, MP_WORKING = 4, MP_FEMALE = 8, MP_CHILD = 16, MP_ELDER = 32 };

/* The people within a box round (x, z) (tiles), at most `max`; returns how many were written. */
int32_t mp_people_near(MPWorld *w, float x, float z, float half_w, float half_h, MPPerson *out, int32_t max);

/* The model of a chunk (32 x 32 tiles): part 0 the ground tops (textured with mp_chunk_ground_rgba),
 * 1 everything standing (walls, steps, furniture: coloured from mp_palette_rgba), 2 plants and rocks as
 * cut-outs (anime atlas). NULL for an empty part. Free with mp_mesh_free. */
MPMesh *mp_chunk_mesh(MPWorld *w, int32_t cx, int32_t cy, int32_t part);
/* The ground picture of a chunk: 32 * px wide and tall, RGBA; returns the side in pixels (call with NULL to ask). */
int32_t mp_chunk_ground_rgba(MPWorld *w, int32_t cx, int32_t cy, uint8_t *out, int32_t cap);

/* Counts, then copies: positions and normals 3 floats a vertex, uvs 2. */
void mp_mesh_counts(const MPMesh *m, int32_t *vertices, int32_t *indices);
void mp_mesh_copy(const MPMesh *m, float *positions, float *normals, float *uvs, uint32_t *indices);
void mp_mesh_free(MPMesh *m);

/* The palette picture the standing parts are coloured from: writes width * height * 4 bytes when `out` is
 * big enough; returns width * 65536 + height. */
int32_t mp_palette_rgba(uint8_t *out, int32_t cap);

/* A person's model as a glTF 2.0 binary (skeleton named as Unreal's mannequin, clips idle, walk, run, work,
 * strike, wave, sit; metres): returns its size, writing it to `out` when `cap` is big enough. 0 for a
 * character model not rigged yet. */
int32_t mp_person_glb(const MPPerson *p, uint8_t *out, int32_t cap);

#ifdef __cplusplus
}
#endif
#endif
