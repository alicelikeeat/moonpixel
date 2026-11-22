/* The C library from C, as Unreal's plugin calls it: make a world, run it, read people and a chunk. */
#include <stdio.h>
#include <stdlib.h>
#include "moonpixel.h"

int main(void) {
    if (sizeof(MPPerson) != 88) { printf("MPPerson is %d bytes, not 88\n", (int)sizeof(MPPerson)); return 1; }
    printf("moonpixel %s (abi %d)\n", mp_version(), mp_abi());
    MPWorld *w = mp_world_create(7, 2, 12);
    if (!w) return 2;
    mp_world_tick(w, 5.0);
    printf("population %d, time %.1f\n", mp_world_population(w), mp_world_time(w));
    MPPerson people[32];
    int n = mp_people_near(w, 0, 0, 200, 200, people, 32);
    for (int i = 0; i < n && i < 3; i++)
        printf("person %d at %.1f,%.1f flags %d skin %06x held '%s' model '%s'\n", people[i].id, people[i].x, people[i].z, people[i].flags, people[i].skin, people[i].held, people[i].model);
    MPMesh *m = mp_chunk_mesh(w, 0, 0, 1);
    int vc = 0, ic = 0;
    mp_mesh_counts(m, &vc, &ic);
    float *pos = malloc(sizeof(float) * 3 * vc), *nor = malloc(sizeof(float) * 3 * vc), *uv = malloc(sizeof(float) * 2 * vc);
    uint32_t *idx = malloc(sizeof(uint32_t) * ic);
    mp_mesh_copy(m, pos, nor, uv, idx);
    printf("chunk 0,0 standing parts: %d vertices, %d triangles\n", vc, ic / 3);
    mp_mesh_free(m);
    int size = n > 0 ? mp_person_glb(&people[0], NULL, 0) : 0;
    printf("person 0 model: %d bytes of glTF\n", size);
    mp_world_destroy(w);
    if (n <= 0 || vc <= 0) return 3;
    puts("ok");
    return 0;
}
