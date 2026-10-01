// Задания старейшины эльфов: выдача, засчитывание делом, награда
// (перенос elder.gd — без тела старейшины и поиска по миру).
namespace DjvaGoda.Core
{
    public class ElfTaskRecord
    {
        public static readonly V3 ElderPosition = new V3(-286f, 0f, 316f);
        public const float ElderRespawn = 180f;

        public ElfTaskKind? Task;
        public int Progress;
        public int TasksDone;
        float _holdSeconds;

        public bool Done { get { return Task.HasValue && Progress >= ElfTasks.TargetOf(Task.Value); } }

        /// Доклад старейшине. enemyLabourers — есть ли у врагов батраки (иначе
        /// «подрубить хозяйство» не даём); headsAlive — жив ли хоть один вожак.
        public string Report(Wallet pay, bool enemyLabourers, bool headsAlive)
        {
            if (!Task.HasValue) return IssueNext(enemyLabourers, headsAlive);
            if (!Done) return "Задание не выполнено: " + ElfTasks.ProgressText(Task.Value, Progress);
            var reward = ElfTasks.RewardOf(Task.Value);
            for (int i = 0; i < reward.Length; i++)
                if (reward[i] > 0) pay.Add(i, reward[i]);
            TasksDone += 1;
            string doneName = ElfTasks.NameOf(Task.Value);
            Task = null;
            Progress = 0;
            return "Задание «" + doneName + "» выполнено. " + IssueNext(enemyLabourers, headsAlive);
        }

        string IssueNext(bool enemyLabourers, bool headsAlive)
        {
            ElfTaskKind kind = ElfTaskKind.Ambush;
            if (TasksDone >= ElfTasks.HeadAfter && headsAlive)
            {
                kind = ElfTaskKind.Head;
            }
            else
            {
                int start = TasksDone % ElfTasks.Rotation.Length;
                for (int step = 0; step < ElfTasks.Rotation.Length; step++)
                {
                    var candidate = ElfTasks.Rotation[(start + step) % ElfTasks.Rotation.Length];
                    if (candidate == ElfTaskKind.Labourers && !enemyLabourers) continue;
                    kind = candidate;
                    break;
                }
            }
            Task = kind;
            Progress = 0;
            _holdSeconds = 0f;
            return "Новое задание: " + ElfTasks.NameOf(kind);
        }

        /// Шахта или хутор: секунды на месте, пока рядом нет чужих.
        public void TickHold(float delta, bool atPlace, int hostilesNear)
        {
            if (Task != ElfTaskKind.Mine && Task != ElfTaskKind.Reclaim) return;
            if (!atPlace || hostilesNear > 0) return;
            _holdSeconds += delta;
            Progress = (int)_holdSeconds;
        }

        /// Конь: верхом в поселении.
        public void TickHorse(bool ridingInVillage)
        {
            if (Task == ElfTaskKind.Horse && ridingInVillage) Progress = ElfTasks.TargetOf(ElfTaskKind.Horse);
        }

        /// Эльф остановил чужой обоз (увёл лошадей, разграбил или разбил).
        public void OnCaravanHit(Faction cartSide)
        {
            if (Task == ElfTaskKind.Ambush && cartSide != Faction.Elves) Progress = ElfTasks.TargetOf(ElfTaskKind.Ambush);
        }

        public void OnKill(Faction victim, bool victimIsLabourer, bool victimIsLeader)
        {
            if (!Factions.Hostile((int)Faction.Elves, (int)victim)) return;
            if (Task == ElfTaskKind.Labourers && victimIsLabourer) Progress += 1;
            if (Task == ElfTaskKind.Head && victimIsLeader) Progress = ElfTasks.TargetOf(ElfTaskKind.Head);
        }
    }
}
