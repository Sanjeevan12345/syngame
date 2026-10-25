# The Siege of Vaikuntha

The Siege of Vaikuntha is a board game for 2 to 4 players, made in Godot. It mixes a property-trading game with a race game, set in the world of the Mahabharata. Each player is a king with 3 pawns and 1000 Gold. You throw two Pasa sticks to move, buy kingdoms as you travel around the outer ring, build Forts and Palaces on them, and collect rent from anyone who lands there. Passing Rajasuya Yajna (Start) earns you 200 Gold, while cards, taxes and the Hall of Dice keep things unpredictable.

From the outer ring, your pawns can enter the inner Ludo track through the gates. Land on a rival's pawn to capture it (a "Vadh") and send it back to Start, but Safe Houses protect pawns from capture. Once you own a full colour set and have made 3 captures, your pawns can take the Home Stretch towards Vaikuntha. The first player to bring all their pawns to Vaikuntha wins. You can also win by being the last player left after everyone else goes bankrupt.

To play, open the project in Godot 4 and press Play. After the intro video (click to skip it), choose the number of players and press "Begin the Siege". You can save and load your game, change the music volume in Settings, and use the magnifier button to zoom in and read the board. Shakuni and Narada will pop up now and then to comment on your moves. Click them to send them away.

---

# Tutorial Guide

## 1. Starting a game

1. Press **Play** in Godot. The intro video plays; click or tap anywhere to skip it.
2. On the opening page, pick **2 Players**, **3 Players** or **4 Players**.
3. Press **Begin the Siege** to start a new game, or **Continue Saga** to load a saved one.
4. The gear in the top-left corner opens **Settings** (mute and music volume).

Everyone plays on the same computer and takes turns. Each player starts with:

- **3 pawns**, all standing on **Rajasuya Yajna** (Start)
- **1000 Gold**

Each player has their own character design, so you can tell the pawns apart.

## 2. The screen

- **The board** is on the left. Around the edge is the **outer ring** of 40 spaces. Inside is the cross-shaped **Ludo track**, and the **Vaikuntha Lotus** is in the middle.
- **The dice box** is at the bottom right. This is where you throw the Pasa sticks.
- **The player panel** shows each player's Gold, Kingdoms, full colour Sets, Kills (captures) and how many pawns have reached Vaikuntha. Each player has **BUILD** and **SELL** buttons here.
- **The Chronicle** is a scrolling log of everything that has happened.
- **The top bar** has these buttons:
  - **↶ Return** goes back to the opening page.
  - **🔍 Magnifier** zooms in on the board.
  - **SAVE**, **LOAD** and **SETTINGS**.

## 3. Taking a turn

1. **Throw the sticks.** Click and hold on the two Pasa sticks in the dice box, drag to swing them, and let go to throw. A faster flick throws harder.
2. **Read your score.** Each stick has four long faces with 0, 1, 2 or 3 dots. Add up the dots on the two top faces. If **both sticks land blank** (0 + 0), that counts as **12**. So you can move 1 to 6, or 12.
3. **Choose a pawn.** The pawns that can use the score start pulsing. Click one to move it. If no pawn can move, your turn passes.
4. **Deal with where you land.** You might buy a kingdom, pay rent, draw a card, capture a rival and so on (see below).
5. The turn then passes to the next player.

Before you throw, you can also **BUILD** on your kingdoms, **SELL** property, or **SAVE** the game.

## 4. The outer ring

Pawns move clockwise around the outer ring.

### Rajasuya Yajna (Start)
Every time your pawn **passes or lands on** Start, you collect **200 Gold**.

### Kingdoms
Kingdoms are the coloured spaces you can buy. They come in **7 colour sets**:

| Set | Kingdoms (price) | Fort cost |
|---|---|---|
| Slate | Vidarbha (80), Kekaya (60), Sarasvata (60) | 50 |
| Pink | Sauvira (120), Karusha (100), Dwarka (100) | 50 |
| Orange | Kamakhya (160), Bahilra (160), Sourastra (140) | 100 |
| Green | Virata (220), Kashi (200), Kuru (180) | 100 |
| Blue | Vanga (280), Shurasena (260), Kushal (240) | 150 |
| Crimson | Malava (340), Kalinga (320), Anga (300) | 150 |
| Black | Gandhara (400), Kosala (360) | 200 |

- **Unowned kingdom:** you are asked whether to **Buy** it or **Pass**. A bought kingdom gets your ownership tag.
- **A rival's kingdom:** you must **pay rent** to its owner.
- **Your own kingdom:** nothing happens.

### Rent
Each kingdom has a base rent. Rent goes up as the owner builds:

| What the owner has | Rent |
|---|---|
| Just the kingdom | Base rent |
| The **full colour set**, no buildings | 2 × base |
| 1 Fort | 4 × base |
| 2 Forts | 10 × base |
| 3 Forts | 20 × base |
| 4 Forts | 30 × base |
| Palace | 40 × base |

### Tax spaces
You pay the Bank when you land here:

- **Vana Daan** (Charity): 60 Gold
- **Yajna Dakshina** (Offering): 200 Gold
- **Rajasva Kara** (Royal Tax): 200 Gold
- **Kurukshetra** (War Levy): 150 Gold

### Reward spaces
The Bank pays you when you land here:

- **Swayamvara:** collect 150 Gold
- **Ashvamedha:** collect 200 Gold
- **Akshaya Patram:** collect 100 Gold

### Lucky and unlucky spaces
- **Gandiva:** roll again straight away.
- **Agyatavasa:** skip your next turn.

### Card spaces
- **Dharma** draws a **Dharma card**. These are mostly good: Gold, tribute from rivals, a free Fort, throwing again, or making a rival skip a turn.
- **Adharma** draws an **Adharma card**. These are mostly bad: losing Gold, paying rivals, repair bills, being sent back to Start, skipping turns, or losing a Fort. One rare good one is **Shakuni's loaded dice**, which lets you **choose your score** on your next turn.

Every card in a deck comes up once before the deck is shuffled again.

### Gates
There are four gates: **Gate Magadha**, **Gate Panchala**, **Gate Indraprastha** and **Gate Gandhara**. If your move **ends on a gate**, you are asked whether to **enter the Ludo board**. Say yes, and the pawn steps onto the Ludo track.

### Other named spaces
Hall of Dice, Dwarka Haven, Kamyaka Forest and Maya Sabha are resting spaces. Nothing happens when you land there, but Shakuni and Narada may have something to say.

## 5. Building Forts and Palaces

Once you own **every kingdom in a colour set**, you can build on that set.

1. At the start of your turn, **before throwing**, press **BUILD** in your row of the player panel.
2. Build **Forts** one at a time, up to **4 per kingdom**. A 5th build turns the 4 Forts into a **Palace**.
3. **Build evenly.** You can't add a second Fort to one kingdom until every kingdom in that set has one, and so on.
4. The Bank has only **32 Forts** and **12 Palaces**. When they run out, nobody can build more until some are sold.

Building costs the set's Fort cost each time (see the table above).

## 6. Selling and debt

- Press **SELL** (at any time) to sell back to the Bank:
  - **A kingdom** sells for **75%** of its price. You can't sell a kingdom while any kingdom in its set still has buildings.
  - **A building** sells for **50%** of its cost. Sell evenly too: you remove buildings from the most-built kingdom first.
- **If you owe more Gold than you have**, the sell panel opens and you must sell until you can pay.
- **If even selling everything isn't enough, you are bankrupt** and out of the game. Your kingdoms go back to the Bank, and your pawns leave the board. If you owed another player, they get everything you had left.

## 7. The Ludo track and capturing (Vadh)

- Once a pawn enters through a gate, it travels around the Ludo track, which is **72 spaces** for a full lap.
- **Vadh (capture):** if your move ends on a space with a rival's pawn, you **capture** it. The rival pawn is sent back to Start (without the 200 Gold bonus), and you gain **1 Kill**. Captures work on the outer ring too. When you capture, the space's normal effect (rent, tax and so on) does not happen.
- **Safe spaces:** pawns can't be captured on **Start**, on the marked **Safe Houses** of the Ludo track, or in the Home Stretch.
- **Leaving the Ludo track:** if your move ends on the tip of a Ludo arm, you may **exit back to the outer ring** through that arm's gate. Your lap progress is lost.

### Finishing a lap
When a pawn completes a full lap back to where it entered:

- **If you qualify** (see below), it turns into the **Home Stretch**.
- **If you don't qualify yet**, you get **200 Gold** and choose either to **loop again** or to **leave** through the gate you came in by.

## 8. The Home Stretch and winning

To turn into the Home Stretch, you need **both** of these:

- at least **1 full colour set**, and
- at least **3 Kills**.

The Home Stretch is **6 spaces** leading to the **Vaikuntha Lotus**. You must land on Vaikuntha with an **exact score**. A throw that would go past it can't be used by that pawn.

**You win when all 3 of your pawns reach Vaikuntha.** You also win if every other player goes bankrupt.

## 9. Handy tools

- **Magnifier (🔍):** click it, then move the mouse over the board to read the small writing. The **mouse wheel** zooms in and out, and **Esc** puts it away. Clicks still go through, so you can keep playing.
- **Save / Load:** you can save **between moves**, before throwing. Saving over a used slot asks you to click twice to confirm.
- **Return (↶):** goes back to the opening page. If the game isn't saved, it asks whether to save first. **LOAD** asks the same.
- **Shakuni and Narada:** they pop up in the bottom-left corner to joke about the game. Click them to dismiss them early.
- **Dev Mode** (top-left of the board) is a testing tool that lets you pick a score instead of throwing. Leave it off for a fair game.

## 10. Tips for new players

- **Buy early.** Cheap sets like Slate and Pink are easy to complete and quick to build on.
- **A full set is everything.** It doubles your rent, lets you build, and is half of what you need to reach the Home Stretch.
- **Hunt for Kills.** You need 3 captures to go home, so chase rival pawns on the Ludo track, and keep yours on Safe Houses when rivals are close.
- **Keep some Gold.** Taxes, rent and Adharma cards can force you to sell kingdoms cheaply.
- **Watch the Chronicle.** It tells you exactly what each card did and who paid whom.
