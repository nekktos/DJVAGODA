// Схема сохранения мира и игроков (перенос savegame.gd).
//
// Классы с открытыми полями и [Serializable]: Unity-слой пишет их через
// JsonUtility, ядро только описывает, ЧТО переживает выход. Почему каждое поле
// обязано сохраняться — в Godot-версии (трофеи, лошади, вставленные глаза…).
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    [Serializable]
    public class SavedBuilding
    {
        public int kind;
        public float x, y, z, yaw;
        public int owner;
        public int faction;
        public float progress;
        public float health;
        public int grade;
    }

    [Serializable]
    public class SavedLabourer
    {
        public int faction;
        public int role;
        public float homeX, homeY, homeZ;
    }

    [Serializable]
    public class SavedTreasury
    {
        public int faction;
        public int[] carried = Res.Empty();
        public int carriedCap;
        public int[] stored = Res.Empty();
        public int storedCap;
        public int horses;
    }

    /// Прогресс игрока — на паре ПРОФИЛЬ + СТОРОНА: у каждой стороны свой.
    [Serializable]
    public class SavedPlayer
    {
        public string profile;
        public int faction;
        public int gearTier;
        public int armorTier;
        public int potionsHeal;
        public int potionsMana;
        public int harnessSize = 2;
        public bool isLeader;
        public int ordersDone;
        public int finalThreshold = Orders.OrdersForFinal;
        public bool alive = true;
        public int severedMask;
        public int crippledMask;
        public int[] prosthetics = new int[4];
        public int eyesLost;
        public int eyeImplants;
        /// Трофеи — чужие руки, ноги, глаза: некротический протез стоит десять.
        public int[] trophies = new int[3];
        /// Состав отряда: 0 — мечник, 1 — лучник. Волков не храним.
        public int[] squad = new int[0];
        public int bandages = BodyState.StartBandages;
        public bool inWheelchair;
        public int experience;
        public int[] upgrades = new int[4];
        /// Прокачка заклинаний по AbilityKind.
        public int[] spellLevels = new int[6];
    }

    [Serializable]
    public class SaveData
    {
        public string worldId;
        public string savedAt;
        public int palaceOwner = (int)Faction.Guard;
        public bool[] leaderDown = new bool[Factions.Count];
        public bool[] victors = new bool[Factions.Count];
        public bool[] outOfMatch = new bool[Factions.Count];
        public bool guardAbsorbed;
        public bool villainAbsorbed;
        public List<SavedBuilding> buildings = new List<SavedBuilding>();
        public List<SavedLabourer> labourers = new List<SavedLabourer>();
        public List<SavedTreasury> treasuries = new List<SavedTreasury>();
        public List<SavedPlayer> players = new List<SavedPlayer>();

        /// Снять с исхода партии.
        public void CaptureMatch(MatchState match)
        {
            palaceOwner = (int)match.PalaceOwner;
            guardAbsorbed = match.GuardAbsorbed;
            villainAbsorbed = match.VillainAbsorbed;
            for (int f = 0; f < Factions.Count; f++)
            {
                leaderDown[f] = match.LeaderDown[f];
                victors[f] = match.Victors[f];
                outOfMatch[f] = match.Out[f];
            }
        }

        /// Вернуть исход партии; союз стражи со злодеем выставляется заново.
        public void RestoreMatch(MatchState match)
        {
            match.PalaceOwner = (Faction)palaceOwner;
            match.GuardAbsorbed = guardAbsorbed;
            match.VillainAbsorbed = villainAbsorbed;
            for (int f = 0; f < Factions.Count; f++)
            {
                match.LeaderDown[f] = leaderDown[f];
                match.Victors[f] = victors[f];
                match.Out[f] = outOfMatch[f];
            }
            match.ApplyAlliances();
        }

        public static SavedTreasury CaptureTreasury(Faction side, Wallet wallet)
        {
            return new SavedTreasury
            {
                faction = (int)side,
                carried = (int[])wallet.Carried.Amounts.Clone(),
                carriedCap = wallet.Carried.Capacity,
                stored = (int[])wallet.Stored.Amounts.Clone(),
                storedCap = wallet.Stored.Capacity,
                horses = wallet.Horses,
            };
        }

        public static void RestoreTreasury(SavedTreasury saved, Wallet wallet)
        {
            wallet.Carried.Amounts = Res.Fit(saved.carried);
            wallet.Carried.Capacity = saved.carriedCap;
            wallet.Stored.Amounts = Res.Fit(saved.stored);
            wallet.Stored.Capacity = saved.storedCap;
            wallet.Horses = saved.horses;
            wallet.HorsesOut = 0;
        }
    }
}
