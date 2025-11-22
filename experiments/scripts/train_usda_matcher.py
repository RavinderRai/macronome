"""
Train XGBoost model to match ingredients to USDA food items.

This script:
1. Contains labeled training data (good vs bad matches)
2. Extracts features from USDA food items
3. Trains XGBoost classifier
4. Tests on real USDA API queries

Requirements:
- xgboost
- pandas
- httpx
- python-dotenv
"""
import os
import sys
import asyncio
from pathlib import Path
from typing import Dict, List, Tuple
import httpx
import pandas as pd
import xgboost as xgb
from dotenv import load_dotenv

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root / "src"))
load_dotenv()

# Training data: (ingredient_name, usda_description, usda_category, label)
# label: 1 = good match, 0 = bad match
TRAINING_DATA = [
    # Chicken - good matches
    ("chicken", "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw", "Poultry Products", 1),
    ("chicken", "Chicken, ground, raw", "Poultry Products", 1),
    ("chicken", "Chicken, feet, boiled", "Poultry Products", 1),
    ("chicken", "Chicken, stewing, meat and skin, raw", "Poultry Products", 1),
    ("chicken", "Chicken, roasting, meat and skin, raw", "Poultry Products", 1),
    ("chicken", "Chicken, broiler or fryers, thigh, meat only, raw", "Poultry Products", 1),
    ("chicken", "Chicken, broiler or fryers, leg, meat only, raw", "Poultry Products", 1),
    ("chicken", "Chicken, broilers or fryers, drumstick, meat only, raw", "Poultry Products", 1),
    ("chicken", "Chicken, broilers or fryers, wing, meat only, raw", "Poultry Products", 1),
    ("chicken", "Chicken, cornish game hens, meat only, raw", "Poultry Products", 1),
    
    # Chicken - bad matches
    ("chicken", "Chicken spread", "Sausages and Luncheon Meats", 0),
    ("chicken", "Chicken, meatless", "Legumes and Legume Products", 0),
    ("chicken", "Fat, chicken", "Fats and Oils", 0),
    ("chicken", "Frankfurter, chicken", "Sausages and Luncheon Meats", 0),
    ("chicken", "Fast foods, chicken tenders", "Fast Foods", 0),
    ("chicken", "Chicken, canned, no broth", "Poultry Products", 0),
    ("chicken", "Chicken, broiler, rotisserie, BBQ, back meat only", "Poultry Products", 0),
    ("chicken", "Chicken patty, frozen, cooked", "Poultry Products", 0),
    ("chicken", "Chicken nuggets, frozen, cooked", "Fast Foods", 0),
    ("chicken", "Chicken roll, light meat", "Sausages and Luncheon Meats", 0),
    
    # Beef - good matches
    ("beef", "Beef, ground, 85 percent lean meat / 15 percent fat, raw", "Beef Products", 1),
    ("beef", "Beef, ground, 90 percent lean meat / 10 percent fat, raw", "Beef Products", 1),
    ("beef", "Beef, ground, 95 percent lean meat / 5 percent fat, raw", "Beef Products", 1),
    ("beef", "Beef, chuck, blade roast, separable lean and fat, raw", "Beef Products", 1),
    ("beef", "Beef, round, top round, separable lean and fat, raw", "Beef Products", 1),
    ("beef", "Beef, loin, top sirloin, separable lean and fat, raw", "Beef Products", 1),
    ("beef", "Beef, brisket, flat half, separable lean and fat, raw", "Beef Products", 1),
    ("beef", "Beef, short loin, t-bone steak, separable lean and fat, raw", "Beef Products", 1),
    ("beef", "Beef, tenderloin, separable lean and fat, raw", "Beef Products", 1),
    ("beef", "Beef, flank, steak, separable lean and fat, raw", "Beef Products", 1),
    
    # Beef - bad matches
    ("beef", "Beef, cured, dried", "Sausages and Luncheon Meats", 0),
    ("beef", "Beef, cured, corned beef, brisket, cooked", "Beef Products", 0),
    ("beef", "Beef, cured, corned beef, brisket, raw", "Beef Products", 0),
    ("beef", "Beef, corned beef hash, with potato, canned", "Meals, Entrees, and Side Dishes", 0),
    ("beef", "Beef jerky, chopped and formed", "Snacks", 0),
    ("beef", "Beef, cured, pastrami", "Sausages and Luncheon Meats", 0),
    ("beef", "Beef, cured, smoked, chopped beef", "Sausages and Luncheon Meats", 0),
    ("beef", "Beef stew, canned entree", "Meals, Entrees, and Side Dishes", 0),
    ("beef", "Beef pot pie, frozen entree", "Meals, Entrees, and Side Dishes", 0),
    ("beef", "Bologna, beef", "Sausages and Luncheon Meats", 0),
    
    # Pork - good matches
    ("pork", "Pork, fresh, ground, raw", "Pork Products", 1),
    ("pork", "Pork, fresh, loin, center loin (chops), bone-in, separable lean and fat, raw", "Pork Products", 1),
    ("pork", "Pork, fresh, shoulder, whole, separable lean and fat, raw", "Pork Products", 1),
    ("pork", "Pork, fresh, loin, tenderloin, separable lean and fat, raw", "Pork Products", 1),
    ("pork", "Pork, fresh, loin, sirloin (chops), bone-in, separable lean and fat, raw", "Pork Products", 1),
    ("pork", "Pork, fresh, spareribs, separable lean and fat, raw", "Pork Products", 1),
    ("pork", "Pork, fresh, leg (ham), whole, separable lean and fat, raw", "Pork Products", 1),
    ("pork", "Pork, fresh, shoulder, blade, boston (roasts), separable lean and fat, raw", "Pork Products", 1),
    
    # Pork - bad matches
    ("pork", "Pork, pickled pork hocks", "Pork Products", 0),
    ("pork", "Pork, cured, salt pork, raw", "Pork Products", 0),
    ("pork", "Pork, cured, bacon, cooked", "Pork Products", 0),
    ("pork", "Pork, cured, ham, boneless, regular, roasted", "Pork Products", 0),
    ("pork", "Bologna, pork", "Sausages and Luncheon Meats", 0),
    ("pork", "Scrapple, pork", "Sausages and Luncheon Meats", 0),
    ("pork", "Bratwurst, pork, cooked", "Sausages and Luncheon Meats", 0),
    ("pork", "Sausage, pork, fresh, cooked", "Pork Products", 0),
    ("pork", "Frankfurter, pork", "Sausages and Luncheon Meats", 0),
    ("pork", "Headcheese, pork", "Sausages and Luncheon Meats", 0),
    
    # Rice - good matches
    ("rice", "Rice, white, long-grain, regular, raw, unenriched", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, white, long-grain, regular, raw, enriched", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, white, long-grain, parboiled, unenriched, dry", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, white, long-grain, parboiled, enriched, dry", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, brown, long-grain, raw", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, brown, medium-grain, raw", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, white, medium-grain, raw, unenriched", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, white, medium-grain, raw, enriched", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, white, short-grain, raw", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, white, glutinous, raw", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, brown, short-grain, raw", "Cereal Grains and Pasta", 1),
    ("rice", "Rice, wild, raw", "Cereal Grains and Pasta", 1),
    
    # Rice - bad matches
    ("rice", "Rice crackers", "Snacks", 0),
    ("rice", "Rice and vermicelli mix, rice pilaf flavor, unprepared", "Meals, Entrees, and Side Dishes", 0),
    ("rice", "Snacks, rice cracker brown rice, plain", "Snacks", 0),
    ("rice", "Rice cakes, brown rice, multigrain", "Snacks", 0),
    ("rice", "Rice cakes, brown rice, plain", "Snacks", 0),
    ("rice", "Rice pudding, ready-to-eat", "Sweets", 0),
    ("rice", "Rice bran, crude", "Cereal Grains and Pasta", 0),
    ("rice", "Rice flour, white", "Cereal Grains and Pasta", 0),
    ("rice", "Rice noodles, cooked", "Cereal Grains and Pasta", 0),
    ("rice", "Rice beverage, unsweetened", "Beverages", 0),
    
    # Tomato - good matches
    ("tomato", "Tomatoes, red, ripe, raw, year round average", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, red, ripe, raw, average", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, red, ripe, cooked", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, red, ripe, cooked, boiled", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, red, ripe, cooked, stewed", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, green, raw", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, cherry, raw", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, grape, raw", "Vegetables and Vegetable Products", 1),
    ("tomato", "Tomatoes, plum, raw", "Vegetables and Vegetable Products", 1),
    
    # Tomato - bad matches
    ("tomato", "Tomatoes, red, ripe, canned, packed in tomato juice", "Vegetables and Vegetable Products", 0),
    ("tomato", "Tomatoes, crushed, canned", "Vegetables and Vegetable Products", 0),
    ("tomato", "Tomato products, canned, paste, without salt added", "Vegetables and Vegetable Products", 0),
    ("tomato", "Tomato sauce, canned, no salt added", "Vegetables and Vegetable Products", 0),
    ("tomato", "Tomato juice, canned", "Vegetables and Vegetable Products", 0),
    ("tomato", "Tomatoes, sun-dried", "Vegetables and Vegetable Products", 0),
    ("tomato", "Tomatoes, sun-dried, packed in oil, drained", "Vegetables and Vegetable Products", 0),
    ("tomato", "Tomato powder", "Vegetables and Vegetable Products", 0),
    ("tomato", "Catsup", "Soups, Sauces, and Gravies", 0),
    ("tomato", "Salsa, ready-to-serve", "Soups, Sauces, and Gravies", 0),
    
    # Cheese - good matches
    ("cheese", "Cheese, cheddar", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, mozzarella, whole milk", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, swiss", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, parmesan, hard", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, provolone", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, monterey", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, feta", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, goat, hard type", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, blue", "Dairy and Egg Products", 1),
    ("cheese", "Cheese, ricotta, whole milk", "Dairy and Egg Products", 1),
    
    # Cheese - bad matches
    ("cheese", "Cheese, pasteurized process, American, without added vitamin D", "Dairy and Egg Products", 0),
    ("cheese", "Cheese spread, cream cheese base", "Dairy and Egg Products", 0),
    ("cheese", "Cheese, imitation", "Dairy and Egg Products", 0),
    ("cheese", "Cheese product, pasteurized process, American, reduced fat", "Dairy and Egg Products", 0),
    ("cheese", "Cheese sauce, prepared from recipe", "Soups, Sauces, and Gravies", 0),
    ("cheese", "Cheese fondue", "Dairy and Egg Products", 0),
    ("cheese", "Cheese, cottage, creamed, large or small curd", "Dairy and Egg Products", 0),
    ("cheese", "Cheese food, pasteurized process, American", "Dairy and Egg Products", 0),
    
    # Oil - good matches
    ("oil", "Oil, olive, salad or cooking", "Fats and Oils", 1),
    ("oil", "Oil, vegetable, canola", "Fats and Oils", 1),
    ("oil", "Oil, sunflower, high oleic", "Fats and Oils", 1),
    ("oil", "Oil, vegetable, soybean", "Fats and Oils", 1),
    ("oil", "Oil, corn, industrial and retail, all purpose salad or cooking", "Fats and Oils", 1),
    ("oil", "Oil, peanut, salad or cooking", "Fats and Oils", 1),
    ("oil", "Oil, sesame, salad or cooking", "Fats and Oils", 1),
    ("oil", "Oil, coconut", "Fats and Oils", 1),
    ("oil", "Oil, vegetable, safflower, salad or cooking, high oleic", "Fats and Oils", 1),
    ("oil", "Oil, avocado", "Fats and Oils", 1),
    
    # Oil - bad matches
    ("oil", "Oil, cooking and salad, ENOVA, 80 percent diglycerides", "Fats and Oils", 0),
    ("oil", "Oil, industrial, soy, fully hydrogenated", "Fats and Oils", 0),
    ("oil", "Salad dressing, mayonnaise type, regular, with salt", "Fats and Oils", 0),
    
    # Flour - good matches
    ("flour", "Wheat flour, white, all-purpose, unenriched", "Cereal Grains and Pasta", 1),
    ("flour", "Wheat flour, white, all-purpose, enriched", "Cereal Grains and Pasta", 1),
    ("flour", "Wheat flour, whole-grain", "Cereal Grains and Pasta", 1),
    ("flour", "Wheat flour, white, bread, enriched", "Cereal Grains and Pasta", 1),
    ("flour", "Wheat flour, white, cake, enriched", "Cereal Grains and Pasta", 1),
    ("flour", "Rice flour, white", "Cereal Grains and Pasta", 1),
    ("flour", "Rice flour, brown", "Cereal Grains and Pasta", 1),
    ("flour", "Corn flour, whole-grain, yellow", "Cereal Grains and Pasta", 1),
    ("flour", "Rye flour, medium", "Cereal Grains and Pasta", 1),
    ("flour", "Oat flour", "Cereal Grains and Pasta", 1),
    
    # Flour - bad matches
    ("flour", "Flour, soy, defatted", "Legumes and Legume Products", 0),
    ("flour", "Flour, sesame seed, high-fat", "Nut and Seed Products", 0),
    ("flour", "Flour, sunflower seed, partially defatted", "Nut and Seed Products", 0),
    
    # Apple - good matches
    ("apple", "Apples, raw, with skin", "Fruits and Fruit Juices", 1),
    ("apple", "Apples, raw, without skin", "Fruits and Fruit Juices", 1),
    ("apple", "Apples, raw, Granny Smith, with skin", "Fruits and Fruit Juices", 1),
    ("apple", "Apples, raw, gala, with skin", "Fruits and Fruit Juices", 1),
    ("apple", "Apples, raw, fuji, with skin", "Fruits and Fruit Juices", 1),
    ("apple", "Apples, raw, red delicious, with skin", "Fruits and Fruit Juices", 1),
    ("apple", "Apples, raw, golden delicious, with skin", "Fruits and Fruit Juices", 1),
    ("apple", "Apples, cooked, boiled, with skin, without added ascorbic acid", "Fruits and Fruit Juices", 1),
    
    # Apple - bad matches
    ("apple", "Apples, canned, sweetened, sliced, drained, heated", "Fruits and Fruit Juices", 0),
    ("apple", "Applesauce, canned, unsweetened, without added ascorbic acid", "Fruits and Fruit Juices", 0),
    ("apple", "Applesauce, canned, sweetened", "Fruits and Fruit Juices", 0),
    ("apple", "Apple juice, canned or bottled, unsweetened", "Fruits and Fruit Juices", 0),
    ("apple", "Apples, dried, sulfured, uncooked", "Fruits and Fruit Juices", 0),
    ("apple", "Apples, frozen, unsweetened, unheated", "Fruits and Fruit Juices", 0),
    
    # Onion - good matches
    ("onion", "Onions, raw", "Vegetables and Vegetable Products", 1),
    ("onion", "Onions, yellow, sauteed", "Vegetables and Vegetable Products", 1),
    ("onion", "Onions, cooked, boiled, drained, without salt", "Vegetables and Vegetable Products", 1),
    ("onion", "Onions, red, raw", "Vegetables and Vegetable Products", 1),
    ("onion", "Onions, white, raw", "Vegetables and Vegetable Products", 1),
    ("onion", "Onions, spring or scallions, raw", "Vegetables and Vegetable Products", 1),
    ("onion", "Onions, sweet, raw", "Vegetables and Vegetable Products", 1),
    ("onion", "Shallots, raw", "Vegetables and Vegetable Products", 1),
    
    # Onion - bad matches
    ("onion", "Onions, dehydrated flakes", "Vegetables and Vegetable Products", 0),
    ("onion", "Onions, canned, solids and liquids", "Vegetables and Vegetable Products", 0),
    ("onion", "Onion powder", "Spices and Herbs", 0),
    ("onion", "Onion rings, breaded, frozen, prepared", "Vegetables and Vegetable Products", 0),
    ("onion", "Onions, frozen, whole, unprepared", "Vegetables and Vegetable Products", 0),
    ("onion", "Onions, pickled", "Vegetables and Vegetable Products", 0),
    
    # Carrot - good matches
    ("carrot", "Carrots, raw", "Vegetables and Vegetable Products", 1),
    ("carrot", "Carrots, cooked, boiled, drained, without salt", "Vegetables and Vegetable Products", 1),
    ("carrot", "Carrots, baby, raw", "Vegetables and Vegetable Products", 1),
    ("carrot", "Carrots, cooked, boiled, drained, with salt", "Vegetables and Vegetable Products", 1),
    
    # Carrot - bad matches
    ("carrot", "Carrots, canned, regular pack, solids and liquids", "Vegetables and Vegetable Products", 0),
    ("carrot", "Carrots, frozen, unprepared", "Vegetables and Vegetable Products", 0),
    ("carrot", "Carrot juice, canned", "Vegetables and Vegetable Products", 0),
    ("carrot", "Carrots, dehydrated", "Vegetables and Vegetable Products", 0),
    
    # Turkey - good matches
    ("turkey", "Turkey, ground, raw", "Poultry Products", 1),
    ("turkey", "Turkey, whole, meat and skin, raw", "Poultry Products", 1),
    ("turkey", "Turkey, breast, meat only, raw", "Poultry Products", 1),
    ("turkey", "Turkey, thigh, meat only, raw", "Poultry Products", 1),
    ("turkey", "Turkey, drumstick, meat only, raw", "Poultry Products", 1),
    ("turkey", "Turkey, wing, meat only, raw", "Poultry Products", 1),
    
    # Turkey - bad matches
    ("turkey", "Turkey bacon, cooked", "Sausages and Luncheon Meats", 0),
    ("turkey", "Turkey, deli meat, smoked", "Sausages and Luncheon Meats", 0),
    ("turkey", "Turkey roll, light meat", "Sausages and Luncheon Meats", 0),
    ("turkey", "Turkey patties, breaded, battered, fried", "Poultry Products", 0),
    ("turkey", "Turkey, canned, meat only, with broth", "Poultry Products", 0),
    
    # Pasta - good matches
    ("pasta", "Pasta, dry, unenriched", "Cereal Grains and Pasta", 1),
    ("pasta", "Pasta, dry, enriched", "Cereal Grains and Pasta", 1),
    ("pasta", "Pasta, whole-wheat, dry", "Cereal Grains and Pasta", 1),
    ("pasta", "Pasta, fresh-refrigerated, plain, as purchased", "Cereal Grains and Pasta", 1),
    ("pasta", "Spaghetti, dry, unenriched", "Cereal Grains and Pasta", 1),
    ("pasta", "Macaroni, dry, unenriched", "Cereal Grains and Pasta", 1),
    
    # Pasta - bad matches
    ("pasta", "Pasta with meatballs in tomato sauce, canned entree", "Meals, Entrees, and Side Dishes", 0),
    ("pasta", "Pasta with sliced franks in tomato sauce, canned entree", "Meals, Entrees, and Side Dishes", 0),
    ("pasta", "Macaroni and cheese, box mix with cheese sauce", "Meals, Entrees, and Side Dishes", 0),
    
    # Potato - good matches
    ("potato", "Potatoes, raw, skin", "Vegetables and Vegetable Products", 1),
    ("potato", "Potatoes, flesh and skin, raw", "Vegetables and Vegetable Products", 1),
    ("potato", "Potatoes, red, flesh and skin, raw", "Vegetables and Vegetable Products", 1),
    ("potato", "Potatoes, white, flesh and skin, raw", "Vegetables and Vegetable Products", 1),
    ("potato", "Potatoes, russet, flesh and skin, raw", "Vegetables and Vegetable Products", 1),
    ("potato", "Potatoes, boiled, cooked without skin, flesh, without salt", "Vegetables and Vegetable Products", 1),
    ("potato", "Sweet potato, raw, unprepared", "Vegetables and Vegetable Products", 1),
    
    # Potato - bad matches
    ("potato", "Potatoes, french fried, all types, frozen, unprepared", "Vegetables and Vegetable Products", 0),
    ("potato", "Potatoes, hash brown, frozen, plain, unprepared", "Vegetables and Vegetable Products", 0),
    ("potato", "Potatoes, mashed, dehydrated, granules without milk", "Vegetables and Vegetable Products", 0),
    ("potato", "Potato chips, plain, salted", "Snacks", 0),
    ("potato", "Potatoes, canned, drained solids", "Vegetables and Vegetable Products", 0),
    
    # Garlic - good matches
    ("garlic", "Garlic, raw", "Vegetables and Vegetable Products", 1),
    ("garlic", "Garlic, cooked", "Vegetables and Vegetable Products", 1),
    
    # Garlic - bad matches
    ("garlic", "Garlic powder", "Spices and Herbs", 0),
    ("garlic", "Garlic, dried", "Spices and Herbs", 0),
    
    # Lettuce - good matches
    ("lettuce", "Lettuce, green leaf, raw", "Vegetables and Vegetable Products", 1),
    ("lettuce", "Lettuce, red leaf, raw", "Vegetables and Vegetable Products", 1),
    ("lettuce", "Lettuce, romaine, raw", "Vegetables and Vegetable Products", 1),
    ("lettuce", "Lettuce, iceberg, raw", "Vegetables and Vegetable Products", 1),
    ("lettuce", "Lettuce, butterhead, raw", "Vegetables and Vegetable Products", 1),
    
    # Lettuce - bad matches
    ("lettuce", "Lettuce, iceberg, greenhouse grown", "Vegetables and Vegetable Products", 0),
    
    # Banana - good matches
    ("banana", "Bananas, raw", "Fruits and Fruit Juices", 1),
    ("banana", "Bananas, ripe and slightly ripe, raw", "Fruits and Fruit Juices", 1),
    ("banana", "Plantains, raw", "Fruits and Fruit Juices", 1),
    
    # Banana - bad matches
    ("banana", "Bananas, dehydrated, or banana powder", "Fruits and Fruit Juices", 0),
    
    # Orange - good matches
    ("orange", "Oranges, raw, all commercial varieties", "Fruits and Fruit Juices", 1),
    ("orange", "Oranges, raw, navels", "Fruits and Fruit Juices", 1),
    ("orange", "Oranges, raw, Florida", "Fruits and Fruit Juices", 1),
    ("orange", "Oranges, raw, California, valencias", "Fruits and Fruit Juices", 1),
    
    # Orange - bad matches
    ("orange", "Orange juice, raw", "Fruits and Fruit Juices", 0),
    ("orange", "Orange juice, frozen concentrate", "Fruits and Fruit Juices", 0),
    ("orange", "Orange peel, raw", "Fruits and Fruit Juices", 0),
    
    # Butter - good matches
    ("butter", "Butter, salted", "Dairy and Egg Products", 1),
    ("butter", "Butter, without salt", "Dairy and Egg Products", 1),
    ("butter", "Butter, whipped, with salt", "Dairy and Egg Products", 1),
    
    # Butter - bad matches
    ("butter", "Margarine, regular, hard, soybean", "Fats and Oils", 0),
    ("butter", "Margarine-like spread, SMART BALANCE Regular Buttery Spread", "Fats and Oils", 0),
    ("butter", "Butter oil, anhydrous", "Dairy and Egg Products", 0),
    
    # Milk - good matches
    ("milk", "Milk, whole, 3.25 percent milkfat", "Dairy and Egg Products", 1),
    ("milk", "Milk, reduced fat, fluid, 2 percent milkfat", "Dairy and Egg Products", 1),
    ("milk", "Milk, lowfat, fluid, 1 percent milkfat", "Dairy and Egg Products", 1),
    ("milk", "Milk, nonfat, fluid, with added vitamin A", "Dairy and Egg Products", 1),
    
    # Milk - bad matches
    ("milk", "Milk, canned, evaporated, with added vitamin A", "Dairy and Egg Products", 0),
    ("milk", "Milk, canned, condensed, sweetened", "Dairy and Egg Products", 0),
    ("milk", "Milk, dry, nonfat, instant", "Dairy and Egg Products", 0),
    ("milk", "Milk, chocolate, fluid, commercial, whole", "Dairy and Egg Products", 0),
    
    # Bread - good matches
    ("bread", "Bread, white, commercially prepared", "Baked Products", 1),
    ("bread", "Bread, whole-wheat, commercially prepared", "Baked Products", 1),
    ("bread", "Bread, french or vienna, toasted", "Baked Products", 1),
    ("bread", "Bread, italian", "Baked Products", 1),
    ("bread", "Bread, rye", "Baked Products", 1),
    
    # Bread - bad matches
    ("bread", "Bread crumbs, dry, grated, plain", "Baked Products", 0),
    ("bread", "Bread stuffing, dry mix", "Baked Products", 0),
    
    # Egg - good matches
    ("egg", "Egg, whole, raw, fresh", "Dairy and Egg Products", 1),
    ("egg", "Egg, white, raw, fresh", "Dairy and Egg Products", 1),
    ("egg", "Egg, yolk, raw, fresh", "Dairy and Egg Products", 1),
    ("egg", "Egg, whole, cooked, hard-boiled", "Dairy and Egg Products", 1),
    ("egg", "Egg, whole, cooked, scrambled", "Dairy and Egg Products", 1),
    
    # Egg - bad matches
    ("egg", "Egg, whole, dried", "Dairy and Egg Products", 0),
    ("egg", "Egg substitute, liquid", "Dairy and Egg Products", 0),
    ("egg", "Egg, white, dried, powder", "Dairy and Egg Products", 0),
]


def extract_nutrition(food: Dict) -> Dict[str, float]:
    """Extract nutrition values from USDA food item."""
    nutrients = {}
    for nutrient in food.get("foodNutrients", []):
        nutrient_id = nutrient.get("nutrientId")
        value = nutrient.get("value", 0)
        
        if nutrient_id == 1008:  # Energy (calories)
            nutrients["calories"] = value
        elif nutrient_id == 1003:  # Protein
            nutrients["protein"] = value
        elif nutrient_id == 1005:  # Carbohydrates
            nutrients["carbs"] = value
        elif nutrient_id == 1004:  # Total fat
            nutrients["fat"] = value
    
    return {
        "calories": nutrients.get("calories", 0),
        "protein": nutrients.get("protein", 0),
        "carbs": nutrients.get("carbs", 0),
        "fat": nutrients.get("fat", 0),
    }


def extract_features(ingredient_name: str, description: str, category: str, 
                    nutrition: Dict[str, float], usda_score: float = 0) -> Dict:
    """Extract features from USDA food item."""
    ingredient_lower = ingredient_name.lower().strip()
    desc_lower = description.lower()
    cat_lower = category.lower()
    
    # String matching features
    exact_match = 1 if desc_lower == ingredient_lower else 0
    starts_with = 1 if desc_lower.startswith(ingredient_lower) else 0
    contains_ingredient = 1 if ingredient_lower in desc_lower else 0
    
    # Word overlap
    ingredient_words = set(ingredient_lower.split())
    desc_words = set(desc_lower.split())
    word_overlap = len(ingredient_words & desc_words)
    
    # Description structure
    word_count = len(desc_lower.split())
    comma_count = desc_lower.count(',')
    desc_length = len(desc_lower)
    
    # Position of ingredient in description
    position = desc_lower.find(ingredient_lower)
    position_ratio = 1.0 - (position / max(len(desc_lower), 1)) if position >= 0 else 0
    
    # Category features
    category_word_count = len(cat_lower.split())
    category_overlap = len(ingredient_words & set(cat_lower.split()))
    
    # Nutrition features
    calories = nutrition.get("calories", 0)
    protein = nutrition.get("protein", 0)
    carbs = nutrition.get("carbs", 0)
    fat = nutrition.get("fat", 0)
    
    # Nutrition ratios
    total_macros = protein + carbs + fat
    protein_ratio = protein / max(total_macros, 1)
    carbs_ratio = carbs / max(total_macros, 1)
    fat_ratio = fat / max(total_macros, 1)
    
    return {
        # String matching
        "exact_match": exact_match,
        "starts_with_ingredient": starts_with,
        "contains_ingredient": contains_ingredient,
        "word_overlap": word_overlap,
        "position_ratio": position_ratio,
        
        # Description structure
        "word_count": word_count,
        "comma_count": comma_count,
        "description_length": desc_length,
        
        # Category
        "category_word_count": category_word_count,
        "category_overlap": category_overlap,
        
        # Nutrition
        "calories": calories,
        "protein": protein,
        "carbs": carbs,
        "fat": fat,
        "protein_ratio": protein_ratio,
        "carbs_ratio": carbs_ratio,
        "fat_ratio": fat_ratio,
        
        # USDA metadata
        "usda_score": usda_score,
        "usda_score_normalized": usda_score / 100.0,  # Normalize to 0-1 range
    }


async def fetch_usda_nutrition(description: str, api_key: str) -> Tuple[Dict[str, float], float]:
    """Fetch nutrition data from USDA API for a given description."""
    search_url = "https://api.nal.usda.gov/fdc/v1/foods/search"
    params = {
        "api_key": api_key,
        "query": description,
        "pageSize": 1,
        "dataType": ["SR Legacy"],
    }
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            response = await client.get(search_url, params=params)
            response.raise_for_status()
            data = response.json()
            
            if data.get("foods"):
                food = data["foods"][0]
                nutrition = extract_nutrition(food)
                usda_score = food.get("score", 0)
                return nutrition, usda_score
        except Exception as e:
            print(f"Error fetching nutrition for '{description}': {e}")
    
    return {"calories": 0, "protein": 0, "carbs": 0, "fat": 0}, 0.0


async def prepare_training_data(api_key: str) -> pd.DataFrame:
    """Prepare training data by fetching nutrition for each example."""
    print("Preparing training data...")
    print(f"Total examples: {len(TRAINING_DATA)}")
    
    rows = []
    for i, (ingredient, description, category, label) in enumerate(TRAINING_DATA):
        if (i + 1) % 10 == 0:
            print(f"  Processing {i+1}/{len(TRAINING_DATA)}...")
        
        nutrition, usda_score = await fetch_usda_nutrition(description, api_key)
        features = extract_features(ingredient, description, category, nutrition, usda_score)
        features["label"] = label
        features["ingredient"] = ingredient
        features["description"] = description
        rows.append(features)
        
        # Small delay to avoid rate limiting
        await asyncio.sleep(0.1)
    
    df = pd.DataFrame(rows)
    print(f"Training data prepared: {len(df)} examples")
    print(f"  Good matches (1): {df['label'].sum()}")
    print(f"  Bad matches (0): {len(df) - df['label'].sum()}")
    
    return df


def train_model(df: pd.DataFrame) -> xgb.XGBClassifier:
    """Train XGBoost model."""
    print("\nTraining XGBoost model...")
    
    # Feature columns (exclude label and metadata)
    feature_cols = [
        "exact_match", "starts_with_ingredient", "contains_ingredient", "word_overlap", "position_ratio",
        "word_count", "comma_count", "description_length",
        "category_word_count", "category_overlap",
        "calories", "protein", "carbs", "fat",
        "protein_ratio", "carbs_ratio", "fat_ratio",
        "usda_score", "usda_score_normalized",
    ]
    
    X = df[feature_cols]
    y = df["label"]
    
    # Train model
    model = xgb.XGBClassifier(
        n_estimators=100,
        max_depth=6,
        learning_rate=0.1,
        random_state=42,
        eval_metric="logloss",
    )
    
    model.fit(X, y)
    
    # Feature importance
    print("\nTop 10 most important features:")
    importance = pd.DataFrame({
        "feature": feature_cols,
        "importance": model.feature_importances_
    }).sort_values("importance", ascending=False)
    print(importance.head(10).to_string(index=False))
    
    # Training accuracy
    train_pred = model.predict(X)
    train_acc = (train_pred == y).mean()
    print(f"\nTraining accuracy: {train_acc:.3f}")
    
    return model


async def test_model(model: xgb.XGBClassifier, api_key: str):
    """Test model on real USDA API queries."""
    print("\n" + "="*80)
    print("Testing model on real USDA API queries")
    print("="*80)
    
    test_ingredients = ["chicken", "beef", "rice", "tomato", "cheese"]
    
    search_url = "https://api.nal.usda.gov/fdc/v1/foods/search"
    feature_cols = [
        "exact_match", "starts_with_ingredient", "contains_ingredient", "word_overlap", "position_ratio",
        "word_count", "comma_count", "description_length",
        "category_word_count", "category_overlap",
        "calories", "protein", "carbs", "fat",
        "protein_ratio", "carbs_ratio", "fat_ratio",
        "usda_score", "usda_score_normalized",
    ]
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        for ingredient in test_ingredients:
            print(f"\nTesting: {ingredient}")
            print("-" * 80)
            
            params = {
                "api_key": api_key,
                "query": ingredient,
                "pageSize": 10,
                "dataType": ["SR Legacy"],
            }
            
            response = await client.get(search_url, params=params)
            data = response.json()
            
            if not data.get("foods"):
                print(f"  No results found")
                continue
            
            # Score each result
            scored_results = []
            for food in data["foods"]:
                description = food.get("description", "")
                category = food.get("foodCategory", "")
                nutrition = extract_nutrition(food)
                usda_score = food.get("score", 0)
                
                features = extract_features(ingredient, description, category, nutrition, usda_score)
                feature_dict = {k: features[k] for k in feature_cols}
                
                # Predict
                X_test = pd.DataFrame([feature_dict])
                score = model.predict_proba(X_test)[0][1]  # Probability of "good match"
                
                scored_results.append((score, food))
            
            # Sort by score
            scored_results.sort(key=lambda x: x[0], reverse=True)
            
            # Show top 3
            print(f"  Top 3 matches:")
            for i, (score, food) in enumerate(scored_results[:3]):
                print(f"    {i+1}. Score: {score:.3f}")
                print(f"       {food.get('description')}")
                print(f"       Category: {food.get('foodCategory')}")
            
            # Best match
            best_score, best_food = scored_results[0]
            print(f"\n  Best match: {best_food.get('description')}")
            print(f"  Score: {best_score:.3f}")
            
            await asyncio.sleep(0.5)  # Rate limiting


async def main():
    """Main function."""
    api_key = os.getenv("USDA_API_KEY")
    if not api_key:
        print("Error: USDA_API_KEY not set in environment")
        return
    
    # Prepare training data
    df = await prepare_training_data(api_key)
    
    # Train model
    model = train_model(df)
    
    # Test model
    await test_model(model, api_key)
    
    print("\n" + "="*80)
    print("Training complete!")
    print("="*80)


if __name__ == "__main__":
    asyncio.run(main())

