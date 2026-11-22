class_name FoRulesText
extends RefCounted
## The short in-game rules reference (pause menu and title screen). The designer's full
## rules are in design/rules.md; keep this in step with them and rules_interpretations.md.

const SECTIONS := [
	["The goal", "Three Quests. In each one you craft a weapon from Ingredients, then test it against a Strength Challenge and a Sharpness Challenge. Sharpness Challenges earn Successes; whoever has the most Successes after the third Quest wins (a tie is a shared win)."],
	["Crafting", "Ingredients are laid out on the table, and Blacksmiths act in snake order (1, 2, 3, 3, 2, 1, ...). Each action costs 1 Action Point (AP): draft an Ingredient, sharpen your weapon, or pass. You start the Quests with 3, 4 and 5 AP. Passing ends your crafting for that Quest, and at 0 AP you're done. Some Ingredients change your AP."],
	["Sharpening", "Up to three times per Quest. The first sharpening adds 1d6 to your dice pool, the second and third add 2d6 each."],
	["Challenges", "When crafting is over, everyone rolls their whole dice pool against the Strength Challenge, then against the Sharpness Challenge. Your Ingredients' Effects and Modifiers change each die, then you may use Reactions such as rerolls and +1s. Results can go below 1 or above 6."],
	["Strength, then Sharpness", "The Strength Challenge can give you a penalty, such as losing dice, lowering every die or letting an opponent reroll some, that applies to your Sharpness roll this Quest. The Sharpness Challenge card says how your final dice score Successes."],
	["Reserving", "After the first and second Quests, everyone reserves one of their Ingredients. A reserved Ingredient stays yours: in later Quests you can draft it again for 1 AP and nobody else can take it. Everything else is discarded."],
	["Turn order", "In the first Quest everyone rolls 2d6 and the highest goes first. In later Quests whoever scored the fewest Successes in the previous Quest goes first; ties roll 2d6."],
	["Reading the table", "Tap any card to read it in full. During a Challenge, tap a die to see how its value was worked out. A gold border means the die scores (or protects you from the penalty); a red border means it triggers the penalty. Cards follow their own text when it breaks these rules."],
]
