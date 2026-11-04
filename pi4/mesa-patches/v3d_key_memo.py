#!/usr/bin/env python3
"""
Pi 4 Mesa patch: skip the SHA1 hash in v3d_get_compiled_shader() when the
shader key is the same as one looked up recently.

Every draw where textures or other state changed, the v3d driver rebuilds the
shader-variant key and finds the compiled variant by hashing the whole key
(SHA1, ~3% of CPU in Doom 3 profiles). Usually the key is identical to one of
the last few. This keeps a tiny per-stage memo (key bytes + result) and checks
it with memcmp first. The memo is cleared whenever variants are freed.

Usage: python3 v3d_key_memo.py <mesa-source-dir>
Safe to run twice. If the source doesn't match the expected code, it changes
nothing and exits with status 2.
"""
import sys, os

MARK = "PI4_KEY_MEMO"
src = sys.argv[1]
hdr = os.path.join(src, "src/gallium/drivers/v3d/v3d_context.h")
prog = os.path.join(src, "src/gallium/drivers/v3d/v3d_program.c")

h = open(hdr).read()
p = open(prog).read()
if MARK in h or MARK in p:
    print("v3d_key_memo: already applied")
    sys.exit(0)

edits = []  # (text, old, new)

# 1. memo storage in the program state object
a = "        struct hash_table *cache[MESA_SHADER_STAGES];\n"
edits.append(("h", a, a + """
        /* PI4_KEY_MEMO: recently used variant keys, checked before hashing */
#define V3D_KEY_MEMO_N 4
#define V3D_KEY_MEMO_MAX 512
        struct {
                const void *uncompiled;
                size_t key_size;
                struct v3d_compiled_shader *shader;
                uint8_t key[V3D_KEY_MEMO_MAX];
        } key_memo[MESA_SHADER_STAGES][V3D_KEY_MEMO_N];
        unsigned key_memo_next[MESA_SHADER_STAGES];
"""))

# 2. check the memo before the hashed lookup, remember cache hits
b = """        struct hash_entry *entry = _mesa_hash_table_search(ht, &cache_key);
        if (entry)
                return entry->data;
"""
edits.append(("p", b, """        /* PI4_KEY_MEMO: identical recent key -> same variant, no hashing */
        const unsigned memo_stage = s->info.stage;
        if (key_size <= V3D_KEY_MEMO_MAX) {
                for (unsigned i = 0; i < V3D_KEY_MEMO_N; i++) {
                        if (v3d->prog.key_memo[memo_stage][i].shader &&
                            v3d->prog.key_memo[memo_stage][i].uncompiled == uncompiled &&
                            v3d->prog.key_memo[memo_stage][i].key_size == key_size &&
                            memcmp(v3d->prog.key_memo[memo_stage][i].key, key, key_size) == 0)
                                return v3d->prog.key_memo[memo_stage][i].shader;
                }
        }

        struct hash_entry *entry = _mesa_hash_table_search(ht, &cache_key);
        if (entry) {
                v3d_key_memo_store(v3d, memo_stage, uncompiled, key, key_size, entry->data);
                return entry->data;
        }
"""))

# 3. remember newly compiled variants too
c = """                _mesa_hash_table_insert(ht, dup_cache_key, shader);
        }
"""
edits.append(("p", c, c + """
        v3d_key_memo_store(v3d, s->info.stage, uncompiled, key, key_size, shader);
"""))

# 4. helper functions, placed right before v3d_get_compiled_shader()
d = """struct v3d_compiled_shader *
v3d_get_compiled_shader(struct v3d_context *v3d,
                        struct v3d_key *key,
                        size_t key_size,
                        struct v3d_uncompiled_shader *uncompiled)
{"""
edits.append(("p", d, """/* PI4_KEY_MEMO helpers */
static void
v3d_key_memo_store(struct v3d_context *v3d, unsigned stage,
                   const void *uncompiled, const void *key, size_t key_size,
                   struct v3d_compiled_shader *shader)
{
        if (key_size > V3D_KEY_MEMO_MAX)
                return;
        unsigned i = v3d->prog.key_memo_next[stage];
        v3d->prog.key_memo_next[stage] = (i + 1) % V3D_KEY_MEMO_N;
        v3d->prog.key_memo[stage][i].uncompiled = uncompiled;
        v3d->prog.key_memo[stage][i].key_size = key_size;
        memcpy(v3d->prog.key_memo[stage][i].key, key, key_size);
        v3d->prog.key_memo[stage][i].shader = shader;
}

static void
v3d_key_memo_clear(struct v3d_context *v3d)
{
        memset(v3d->prog.key_memo, 0, sizeof(v3d->prog.key_memo));
}

""" + d))

# 5. clear the memo wherever variants are freed
e = """                _mesa_hash_table_remove(v3d->prog.cache[s->info.stage], entry);
                v3d_free_compiled_shader(shader);
"""
edits.append(("p", e, """                v3d_key_memo_clear(v3d);
""" + e))
f = """                hash_table_foreach(cache, entry) {
                        struct v3d_compiled_shader *shader = entry->data;
                        v3d_free_compiled_shader(shader);
"""
edits.append(("p", f, """                v3d_key_memo_clear(v3d);
""" + f))

# verify every anchor first, then apply
texts = {"h": h, "p": p}
for which, old, new in edits:
    n = texts[which].count(old)
    if n != 1:
        print("v3d_key_memo: source doesn't match (anchor found %d times):\n%s" % (n, old))
        print("v3d_key_memo: NOT applied, building unpatched")
        sys.exit(2)
for which, old, new in edits:
    texts[which] = texts[which].replace(old, new)
open(hdr, "w").write(texts["h"])
open(prog, "w").write(texts["p"])
print("v3d_key_memo: applied")
