// Живой фон (перенос audio/ambience.gd): ветер, птицы, стрекот. Без него
// между ударами стоит полная тишина — живой отчёт Godot-версии назвал это
// «игра ощущается пустынной».
//
// Главное правило оттуда же: непрерывным может быть только бесформенный слой
// (шум ветра). Всё с узнаваемым рисунком — щебет, стрекот — звучит РЕДКО и
// через неровные промежутки; петля стрекота раз в секунду «очень очень
// надоедает жутко». Птицы рождаются вокруг слушателя и сверху, в лесу
// эльфов — втрое чаще.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Ambience : MonoBehaviour
    {
        const float Near = 26f;
        static readonly Vector2 BirdGap = new Vector2(11f, 30f);
        static readonly Vector2 CricketGap = new Vector2(25f, 40f);
        const float ForestBirds = 3f;
        const float ForestRange = 260f;

        public static Ambience Instance { get; private set; }

        AudioSource _wind, _crickets;
        readonly AudioSource[] _voices = new AudioSource[4];
        readonly AudioClip[] _birds = new AudioClip[4];
        int _next;
        float _untilBird = 3f, _untilCricket = 12f;

        void Awake()
        {
            Instance = this;
            _wind = Flat("Ветер", Synth.Wind(), 0f, true);
            _crickets = Flat("Стрекот", Synth.Cricket(), 0.06f, false);
            for (int i = 0; i < _voices.Length; i++)
            {
                var voice = new GameObject("Птица " + i).AddComponent<AudioSource>();
                voice.transform.SetParent(transform, false);
                voice.playOnAwake = false;
                voice.spatialBlend = 1f;
                voice.rolloffMode = AudioRolloffMode.Linear;
                voice.minDistance = 4f;
                voice.maxDistance = 60f;
                voice.dopplerLevel = 0f;
                _voices[i] = voice;
            }
            for (int i = 0; i < _birds.Length; i++) _birds[i] = Synth.Bird(i);
        }

        void OnDestroy() { if (Instance == this) Instance = null; }

        AudioSource Flat(string name, AudioClip clip, float volume, bool loop)
        {
            var source = new GameObject(name).AddComponent<AudioSource>();
            source.transform.SetParent(transform, false);
            source.playOnAwake = false;
            source.spatialBlend = 0f;
            source.clip = clip;
            source.volume = volume;
            source.loop = loop;
            return source;
        }

        /// Фон звучит, только пока идёт партия (в меню птицам петь незачем).
        // Ветер порывами (playtest-10: «противный, звучит постоянно без
        // перерыва»): порыв 6–14 с нарастает и спадает, между порывами 15–40 с
        // тишины. Громкость порыва — разная, пик тише прежнего ровного гула.
        const float GustPeak = 0.22f;
        float _gustLeft, _gustLength = 1f, _calmLeft = 8f, _gustLevel;

        void Gusts(float delta)
        {
            if (_gustLeft > 0f)
            {
                _gustLeft -= delta;
                float t = 1f - Mathf.Clamp01(_gustLeft / _gustLength);
                _wind.volume = _gustLevel * Mathf.Sin(t * Mathf.PI);
                if (_gustLeft <= 0f) _calmLeft = Random.Range(15f, 40f);
                return;
            }
            _wind.volume = 0f;
            _calmLeft -= delta;
            if (_calmLeft > 0f) return;
            _gustLength = _gustLeft = Random.Range(6f, 14f);
            _gustLevel = GustPeak * Random.Range(0.5f, 1f);
        }

        static bool InMatch() { return !Sfx.Muted && MatchGoals.Instance != null; }

        void Update()
        {
            var ears = Sfx.Ears();
            bool on = ears != null && InMatch();
            if (on != _wind.isPlaying)
            {
                if (on) _wind.Play();
                else { _wind.Stop(); _crickets.Stop(); }
            }
            if (!on) return;
            Gusts(Time.deltaTime);
            _untilCricket -= Time.deltaTime;
            if (_untilCricket <= 0f)
            {
                _untilCricket = Random.Range(CricketGap.x, CricketGap.y);
                _crickets.pitch = Random.Range(0.92f, 1.08f);
                _crickets.Play();
            }
            _untilBird -= Time.deltaTime * BirdRate(ears.position);
            if (_untilBird > 0f) return;
            _untilBird = Random.Range(BirdGap.x, BirdGap.y);
            Sing(ears.position);
        }

        static float BirdRate(Vector3 here)
        {
            var forest = Factions.Spawn[(int)Faction.Elves].ToUnity();
            float far = new Vector2(here.x - forest.x, here.z - forest.z).magnitude;
            return far >= ForestRange ? 1f : Mathf.Lerp(ForestBirds, 1f, far / ForestRange);
        }

        void Sing(Vector3 around)
        {
            var voice = _voices[_next];
            _next = (_next + 1) % _voices.Length;
            float angle = Random.value * Mathf.PI * 2f;
            float away = Random.Range(Near * 0.4f, Near);
            // Сверху: щебет из-под ног звучит как что-то другое.
            voice.transform.position = around + new Vector3(Mathf.Cos(angle) * away, Random.Range(3f, 9f), Mathf.Sin(angle) * away);
            voice.clip = _birds[Random.Range(0, _birds.Length)];
            voice.pitch = Random.Range(0.88f, 1.18f);
            voice.volume = Random.Range(0.25f, 0.5f);
            voice.Play();
        }
    }
}
