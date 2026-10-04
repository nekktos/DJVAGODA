// Эффекты боя (перенос combat/effects.gd). Рейтинг 21+ (GDD, разделы 3–4):
// кровь — без смягчения. Только картинка, на игру не влияет; запускается
// на каждом пире от того, что и так видно у всех (падение здоровья —
// Sfx, разрыв снаряда — Shot), поэтому своих RPC не нужно.
//
// Частицы — один ParticleSystem на вид, переиспользуется: Emit в точку,
// а не новый объект на каждый удар.
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Effects
    {
        static readonly Color BloodColor = new Color(0.45f, 0.02f, 0.02f, 1f);
        static readonly Color FireColor = new Color(1f, 0.55f, 0.15f, 1f);

        static ParticleSystem _blood, _fire, _chips;
        static Material _material;

        /// Брызги крови: чем сильнее удар, тем гуще.
        public static void Blood(Vector3 at, Vector3 direction, float amount)
        {
            int count = Mathf.Clamp(Mathf.RoundToInt(amount * 0.8f), 8, 64);
            Burst(ref _blood, "Кровь", at, direction, count, BloodColor, 0.12f, 5f, 1.6f, 1f);
        }

        /// Разрыв огненного шара: искры и огонь во все стороны.
        public static void Explosion(Vector3 at, float radius)
        {
            Burst(ref _fire, "Огонь", at, Vector3.up, 64, FireColor, 0.35f, radius * 1.6f, 0.9f, 0.4f);
        }

        /// Щепки и осколки добычи — цветом ресурса.
        public static void Chips(Vector3 at, Color color)
        {
            Burst(ref _chips, "Щепки", at, Vector3.up, 18, color, 0.08f, 3.5f, 1f, 1f);
        }

        static void Burst(ref ParticleSystem system, string name, Vector3 at, Vector3 direction, int count,
            Color color, float size, float speed, float life, float gravity)
        {
            if (Sfx.Muted) return;
            if (system == null) system = Make(name, gravity);
            if (system == null) return;
            var dir = direction.sqrMagnitude > 0.0001f ? direction.normalized : Vector3.up;
            var emit = new ParticleSystem.EmitParams { applyShapeToPosition = false };
            for (int i = 0; i < count; i++)
            {
                // Конус 60° вокруг направления удара.
                var spread = Random.insideUnitSphere * 0.9f;
                var v = (dir + spread).normalized * Random.Range(speed * 0.4f, speed);
                emit.position = at;
                emit.velocity = v;
                emit.startSize = size * Random.Range(0.5f, 1.4f);
                emit.startLifetime = life * Random.Range(0.7f, 1f);
                emit.startColor = color * Random.Range(0.8f, 1.1f);
                system.Emit(emit, 1);
            }
        }

        static ParticleSystem Make(string name, float gravity)
        {
            if (_material == null)
            {
                var template = Resources.Load<Material>("Particle");
                if (template == null) return null;
                _material = new Material(template) { name = "Частицы" };
                _material.SetTexture("_BaseMap", Dot());
            }
            var go = new GameObject("Эффект: " + name);
            Object.DontDestroyOnLoad(go);
            var system = go.AddComponent<ParticleSystem>();
            system.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = system.main;
            main.loop = false;
            main.playOnAwake = false;
            main.maxParticles = 2000;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.gravityModifier = gravity;
            var emission = system.emission;
            emission.enabled = false;
            var shape = system.shape;
            shape.enabled = false;
            // Гаснут к концу жизни: брызги не исчезают рывком.
            var fade = system.colorOverLifetime;
            fade.enabled = true;
            var gradient = new Gradient();
            gradient.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) },
                new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 0.6f), new GradientAlphaKey(0f, 1f) });
            fade.color = gradient;
            var renderer = go.GetComponent<ParticleSystemRenderer>();
            renderer.sharedMaterial = _material;
            renderer.renderMode = ParticleSystemRenderMode.Billboard;
            renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            system.Play();
            return system;
        }

        /// Мягкая круглая точка 32×32 — частица без квадратных краёв.
        static Texture2D Dot()
        {
            const int n = 32;
            var texture = new Texture2D(n, n, TextureFormat.RGBA32, false) { name = "точка", wrapMode = TextureWrapMode.Clamp };
            var pixels = new Color[n * n];
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float dx = (x + 0.5f) / n * 2f - 1f, dy = (y + 0.5f) / n * 2f - 1f;
                    float a = Mathf.Clamp01(1f - Mathf.Sqrt(dx * dx + dy * dy));
                    pixels[y * n + x] = new Color(1f, 1f, 1f, Mathf.SmoothStep(0f, 1f, a * 1.6f));
                }
            texture.SetPixels(pixels);
            texture.Apply();
            return texture;
        }
    }
}
