// Генератор случайных чисел ядра (SplitMix64).
//
// Свой, а не System.Random: лес и рельеф строятся по зерну НА КАЖДОЙ машине, и
// хост на Windows обязан получить те же деревья, что клиент на macOS. Алгоритм
// System.Random от среды выполнения не обещан; этот — задан здесь целиком.
namespace DjvaGoda.CoreOld
{
    public class Rng
    {
        ulong _state;

        public Rng(long seed) { _state = (ulong)seed; }

        public ulong NextULong()
        {
            ulong z = (_state += 0x9E3779B97F4A7C15UL);
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }

        /// Равномерно в [0, 1).
        public double NextDouble() { return (NextULong() >> 11) * (1.0 / 9007199254740992.0); }

        /// Равномерно в [0, maxExclusive).
        public int Next(int maxExclusive)
        {
            if (maxExclusive <= 0) return 0;
            return (int)(NextULong() % (ulong)maxExclusive);
        }
    }
}
