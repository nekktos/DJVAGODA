// Звуки игры — свои, синтезом (решение автора от 02.10: «всё самостоятельно»;
// в Godot-версии синтез был запасным путём под записями Kenney — здесь он
// единственный). Каждый звук — короткий массив отсчётов, собранный из
// простых кирпичей: шум с фильтром, затухающий тон, щипок струны
// (Карплус — Стронг), огибающая. Детерминированно (зерно), моно, 22 кГц.
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Synth
    {
        public const int Rate = 22050;

        static AudioClip Clip(string name, float[] data)
        {
            var clip = AudioClip.Create(name, data.Length, 1, Rate, false);
            clip.SetData(data, 0);
            return clip;
        }

        static float[] Buffer(float seconds) { return new float[Mathf.Max(1, (int)(seconds * Rate))]; }

        /// Белый шум с однополюсным фильтром: bright 0 — глухой, 1 — шипящий.
        static void Noise(float[] d, float level, float bright, float attack, float decay, int seed, int from = 0)
        {
            var rng = new System.Random(seed);
            float low = 0f;
            float a = Mathf.Lerp(0.02f, 0.9f, bright);
            for (int i = from; i < d.Length; i++)
            {
                float t = (i - from) / (float)Rate;
                float env = Env(t, attack, decay);
                float n = (float)rng.NextDouble() * 2f - 1f;
                low += a * (n - low);
                d[i] += low * level * env;
            }
        }

        /// Тон со сдвигом частоты (from → to) и экспоненциальным затуханием.
        static void Tone(float[] d, float level, float fromHz, float toHz, float attack, float decay, int from = 0, float shape = 0f)
        {
            float phase = 0f;
            float length = (d.Length - from) / (float)Rate;
            for (int i = from; i < d.Length; i++)
            {
                float t = (i - from) / (float)Rate;
                float hz = Mathf.Lerp(fromHz, toHz, Mathf.Clamp01(t / Mathf.Max(0.001f, length)));
                phase += hz / Rate;
                float s = Mathf.Sin(phase * Mathf.PI * 2f);
                // shape > 0 — добавить нечётные гармоники (звонче, «металл»).
                if (shape > 0f) s += shape * (Mathf.Sin(phase * Mathf.PI * 6f) * 0.5f + Mathf.Sin(phase * Mathf.PI * 10f) * 0.25f);
                d[i] += s * level * Env(t, attack, decay);
            }
        }

        /// Щипок струны (Карплус — Стронг): тетива, звон.
        static void Pluck(float[] d, float level, float hz, float damping, int seed, int from = 0)
        {
            int period = Mathf.Max(2, (int)(Rate / hz));
            var line = new float[period];
            var rng = new System.Random(seed);
            for (int i = 0; i < period; i++) line[i] = (float)rng.NextDouble() * 2f - 1f;
            int k = 0;
            for (int i = from; i < d.Length; i++)
            {
                int next = (k + 1) % period;
                float v = line[k];
                line[k] = (line[k] + line[next]) * 0.5f * damping;
                k = next;
                d[i] += v * level;
            }
        }

        static float Env(float t, float attack, float decay)
        {
            if (t < attack) return t / Mathf.Max(0.0001f, attack);
            return Mathf.Exp(-(t - attack) / Mathf.Max(0.0001f, decay));
        }

        /// Мягкий ограничитель: сумма кирпичей не хрипит.
        static float[] Finish(float[] d, float gain = 1f, bool tailFade = true)
        {
            for (int i = 0; i < d.Length; i++) d[i] = (float)System.Math.Tanh(d[i] * gain);
            if (!tailFade) return d;
            // Короткий спад в самом конце — без щелчка.
            int tail = Mathf.Min(d.Length, Rate / 200);
            for (int i = 0; i < tail; i++) d[d.Length - 1 - i] *= i / (float)tail;
            return d;
        }

        /// Петля без щелчка: хвост вплавляется в начало и отрезается — после
        /// последнего отсчёта ровно продолжается первый.
        static float[] Seam(float[] d, int fade)
        {
            int length = d.Length - fade;
            var loop = new float[length];
            for (int i = 0; i < length; i++)
            {
                float w = i < fade ? i / (float)fade : 1f;
                loop[i] = d[i] * w + (i < fade ? d[length + i] * (1f - w) : 0f);
            }
            return loop;
        }

        // --- звуки -----------------------------------------------------------

        public static AudioClip HitFlesh(int seed)
        {
            // Глухой шлепок: шум под фильтром и короткий низкий толчок без
            // скольжения высоты (скольжение звучало мультяшным «буумп» — playtest-10).
            var d = Buffer(0.18f);
            Noise(d, 0.9f, 0.3f, 0.001f, 0.035f, seed);
            Noise(d, 0.35f, 0.7f, 0.0005f, 0.012f, seed + 7);
            Tone(d, 0.45f, 85f, 80f, 0.001f, 0.025f);
            return Clip("удар по живому", Finish(d, 1.3f));
        }

        public static AudioClip HitWood(int seed)
        {
            var d = Buffer(0.25f);
            Noise(d, 0.6f, 0.6f, 0.001f, 0.025f, seed);
            Tone(d, 0.5f, 420f, 380f, 0.001f, 0.05f);
            Tone(d, 0.3f, 780f, 700f, 0.001f, 0.03f);
            Tone(d, 0.35f, 190f, 170f, 0.001f, 0.08f);
            return Clip("удар по дереву", Finish(d, 1.4f));
        }

        public static AudioClip HitStone(int seed)
        {
            var d = Buffer(0.35f);
            Noise(d, 0.6f, 0.95f, 0.0005f, 0.02f, seed);
            Tone(d, 0.35f, 2300f, 2200f, 0.0005f, 0.07f, 0, 0.5f);
            Tone(d, 0.25f, 3400f, 3300f, 0.0005f, 0.05f);
            Tone(d, 0.3f, 260f, 200f, 0.001f, 0.05f);
            return Clip("удар по камню", Finish(d, 1.3f));
        }

        public static AudioClip Swing(int seed)
        {
            var d = Buffer(0.28f);
            var rng = new System.Random(seed);
            float low = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                // Свист: фильтр раскрывается к середине взмаха и закрывается.
                float bright = Mathf.Sin(Mathf.Clamp01(t / 0.28f) * Mathf.PI);
                float n = (float)rng.NextDouble() * 2f - 1f;
                low += Mathf.Lerp(0.03f, 0.35f, bright) * (n - low);
                d[i] = low * 0.9f * bright;
            }
            return Clip("взмах", Finish(d, 1.5f));
        }

        public static AudioClip Bow(int seed)
        {
            var d = Buffer(0.45f);
            Pluck(d, 0.7f, 140f, 0.994f, seed);
            Noise(d, 0.25f, 0.8f, 0.001f, 0.03f, seed + 1);
            return Clip("тетива", Finish(d, 1.2f));
        }

        public static AudioClip Crossbow(int seed)
        {
            var d = Buffer(0.4f);
            Pluck(d, 0.6f, 95f, 0.99f, seed);
            Tone(d, 0.6f, 120f, 70f, 0.001f, 0.05f);
            Noise(d, 0.4f, 0.5f, 0.001f, 0.03f, seed + 1);
            return Clip("арбалет", Finish(d, 1.3f));
        }

        public static AudioClip Fireball(int seed)
        {
            // Гул огня: шум, нарастающий и спадающий; без тона — восходящий тон
            // звучал свистком из мультфильма.
            var d = Buffer(0.6f);
            Noise(d, 0.7f, 0.25f, 0.1f, 0.22f, seed);
            Noise(d, 0.25f, 0.6f, 0.05f, 0.12f, seed + 3);
            return Clip("бросок огня", Finish(d, 1.4f));
        }

        public static AudioClip Explosion(int seed)
        {
            var d = Buffer(1.4f);
            Noise(d, 1.2f, 0.12f, 0.003f, 0.35f, seed);
            Noise(d, 0.5f, 0.6f, 0.001f, 0.06f, seed + 1);
            Tone(d, 0.9f, 75f, 35f, 0.004f, 0.4f);
            return Clip("разрыв", Finish(d, 1.6f));
        }

        public static AudioClip Death(int seed)
        {
            // Тело оземь: два глухих удара шумом и низкий толчок без съезда высоты.
            var d = Buffer(0.5f);
            Noise(d, 0.8f, 0.15f, 0.004f, 0.08f, seed);
            Tone(d, 0.4f, 70f, 66f, 0.003f, 0.05f);
            Noise(d, 0.45f, 0.15f, 0.002f, 0.07f, seed + 1, Rate / 6);
            return Clip("падение", Finish(d, 1.4f));
        }

        public static AudioClip BuildDone()
        {
            var d = Buffer(1.2f);
            Tone(d, 0.35f, 523f, 523f, 0.005f, 0.5f, 0, 0.3f);
            Tone(d, 0.3f, 784f, 784f, 0.005f, 0.6f, Rate / 8, 0.3f);
            Tone(d, 0.25f, 1046f, 1046f, 0.005f, 0.5f, Rate / 4);
            return Clip("достроено", Finish(d));
        }

        public static AudioClip Magic()
        {
            var d = Buffer(1.0f);
            float[] notes = { 659f, 880f, 1175f, 1568f };
            for (int i = 0; i < notes.Length; i++) Tone(d, 0.22f, notes[i], notes[i] * 1.01f, 0.01f, 0.35f, i * Rate / 12);
            Noise(d, 0.08f, 0.95f, 0.05f, 0.3f, 7);
            return Clip("магия", Finish(d));
        }

        public static AudioClip Curse()
        {
            var d = Buffer(0.9f);
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                // Два близких низких тона — биения, дрожь.
                float s = Mathf.Sin(2f * Mathf.PI * 110f * t) + Mathf.Sin(2f * Mathf.PI * 116.5f * t) * 0.8f + Mathf.Sin(2f * Mathf.PI * 164f * t) * 0.4f;
                d[i] = s * 0.3f * Env(t, 0.08f, 0.35f) * (0.75f + 0.25f * Mathf.Sin(2f * Mathf.PI * 9f * t));
            }
            Noise(d, 0.15f, 0.15f, 0.05f, 0.3f, 11);
            return Clip("проклятие", Finish(d, 1.2f));
        }

        public static AudioClip Notice()
        {
            var d = Buffer(0.5f);
            Tone(d, 0.3f, 880f, 880f, 0.003f, 0.12f, 0, 0.2f);
            Tone(d, 0.3f, 1320f, 1320f, 0.003f, 0.15f, Rate / 10, 0.2f);
            return Clip("объявление", Finish(d));
        }

        public static AudioClip Step(int seed)
        {
            var d = Buffer(0.12f);
            Noise(d, 0.5f, 0.35f, 0.004f, 0.03f, seed);
            Tone(d, 0.25f, 90f, 60f, 0.002f, 0.025f);
            return Clip("шаг", Finish(d, 1.2f));
        }

        public static AudioClip Hoof(int seed)
        {
            // Копыто о землю — глухо: звонкий тон давал «кокосовые половинки».
            var d = Buffer(0.14f);
            Noise(d, 0.7f, 0.35f, 0.0005f, 0.02f, seed);
            Tone(d, 0.35f, 150f, 140f, 0.001f, 0.02f);
            return Clip("копыто", Finish(d, 1.3f));
        }

        /// Обоз: скрип осей и глухой перекат — петля в секунду.
        public static AudioClip Cart()
        {
            var d = Buffer(1f);
            Noise(d, 0.35f, 0.08f, 0f, 1000f, 21);
            for (int k = 0; k < 2; k++)
            {
                int at = k * Rate / 2;
                Tone(d, 0.15f, 520f, 610f, 0.04f, 0.12f, at, 0.4f);
            }
            return Clip("обоз", Seam(Finish(d, 1f, false), Rate / 20));
        }

        public static AudioClip Squirrel(int seed)
        {
            var d = Buffer(0.35f);
            var rng = new System.Random(seed);
            int chirps = 4 + rng.Next(3);
            for (int c = 0; c < chirps; c++)
                Tone(d, 0.22f, 1700f + rng.Next(400), 2300f + rng.Next(400), 0.002f, 0.018f, c * Rate / 22, 0.15f);
            return Clip("белка", Finish(d));
        }

        /// Ветер: тёмный шум с медленно дышащей громкостью — петля 6 с.
        public static AudioClip Wind()
        {
            var d = Buffer(6f);
            var rng = new System.Random(31);
            float low = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)Rate;
                float n = (float)rng.NextDouble() * 2f - 1f;
                float gust = 0.6f + 0.4f * Mathf.Sin(2f * Mathf.PI * t / 6f) * Mathf.Sin(2f * Mathf.PI * t / 2f);
                low += 0.02f * gust * (n - low);
                d[i] = low * 1.8f * gust;
            }
            return Clip("ветер", Seam(Finish(d, 1f, false), Rate / 4));
        }

        /// Щебет: 2–4 ноты со скольжением вверх (скольжение и делает его птицей).
        /// Ниже и не чистым тоном: в Godot ровный тон 2–3 кГц игроки назвали
        /// «писком прибора», который «бьёт по ушам».
        public static AudioClip Bird(int seed)
        {
            var rng = new System.Random(5150 + seed * 37);
            int notes = 2 + rng.Next(3);
            var d = Buffer(0.1f * notes + 0.06f);
            float phase = 0f;
            float[] bases = new float[notes];
            for (int n = 0; n < notes; n++) bases[n] = 1500f + n * ((float)rng.NextDouble() * 520f - 200f);
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)d.Length;
                int slot = Mathf.Min(notes - 1, (int)(t * notes));
                float inside = t * notes % 1f;
                phase += (bases[slot] + inside * 620f) / Rate;
                float env = Mathf.Pow(Mathf.Sin(inside * Mathf.PI), 1.6f);
                d[i] = (Mathf.Sin(phase * Mathf.PI * 2f) * 0.75f + Mathf.Sin(phase * Mathf.PI * 4f) * 0.18f) * env * 0.5f;
            }
            return Clip("птица", d);
        }

        /// Стрекот: одна трель из четырёх серий мягких импульсов (приподнятый
        /// косинус, без прямоугольных краёв — у них гармоники режут уши).
        public static AudioClip Cricket()
        {
            var d = Buffer(1.4f);
            float phase = 0f, low = 0f;
            const int pulse = 46, voiced = 15;
            for (int i = 0; i < d.Length; i++)
            {
                float t = i / (float)d.Length;
                phase += 3400f / Rate;
                int k = i % pulse;
                float shape = k < voiced ? 0.5f - 0.5f * Mathf.Cos(2f * Mathf.PI * k / voiced) : 0f;
                float inside = t * 4f % 1f;
                float burst = inside < 0.55f ? 0.5f - 0.5f * Mathf.Cos(2f * Mathf.PI * inside / 0.55f) : 0f;
                float edge = Mathf.Min(1f, Mathf.Min(t, 1f - t) * 14f);
                low = Mathf.Lerp(low, Mathf.Sin(phase * Mathf.PI * 2f) * shape * burst * edge, 0.55f);
                d[i] = low * 0.35f;
            }
            return Clip("стрекот", d);
        }
    }
}
