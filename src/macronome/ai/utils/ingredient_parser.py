"""
Ingredient parsing utility for converting recipe ingredient strings to ParsedIngredient.
"""
import re
from macronome.ai.schemas.recipe_schema import ParsedIngredient


def parse_ingredient(ing_str: str) -> ParsedIngredient:
    """
    Parse ingredient string into ParsedIngredient.
    
    Handles:
    - Simple: "2 cups flour"
    - With periods: "1 c. flour", "2 Tbsp. butter"
    - With parentheses: "2 (16 oz.) pkg. frozen corn"
    - Mixed fractions: "3 1/2 c. sugar", "1 1/2 lb. chicken"
    - Fraction numbers: "34 lb pasta" (34 = 3/4)
    - Container units: "1 can soup", "1 jar sauce"
    - Size descriptors: "1 small jar", "1 large can"
    
    Args:
        ing_str: Raw ingredient string
        
    Returns:
        ParsedIngredient with quantity, unit, and ingredient name
    """
    if not ing_str or not ing_str.strip():
        return ParsedIngredient(
            ingredient=ing_str,
            quantity=1.0,
            unit="serving",
            modifier=None,
        )
    
    original_str = ing_str
    ing_str = ing_str.strip()
    
    # Extract and remove trailing modifiers (optional, divided, etc.)
    modifier = None
    modifier_patterns = [
        r',\s*(optional|divided|to taste|cooked|crumbled|diced|chopped|sliced|cubed|cut up|beaten|drained|thawed|crushed).*$',
        r'\s+(optional|divided)$'
    ]
    for pattern in modifier_patterns:
        match = re.search(pattern, ing_str, re.IGNORECASE)
        if match:
            modifier = match.group(1) if ',' in pattern else match.group(0).strip()
            ing_str = ing_str[:match.start()].strip()
            break
    
    # Preprocessing: fix common formatting issues
    
    # 1. Remove periods from unit abbreviations (c., oz., lb., Tbsp., tsp., pkg.)
    ing_str = re.sub(r'\b(c|oz|lb|lbs|pkg|Tbsp|tbsp|Tsp|tsp)\.', r'\1', ing_str)
    
    # 2. Add space between quantity and unit if missing (e.g., "1/4Cup" -> "1/4 Cup")
    ing_str = re.sub(r'(\d+/\d+|[0-9.]+)([A-Z][a-z]+)', r'\1 \2', ing_str)
    
    # 3. Handle "To Taste" phrases - remove them
    ing_str = re.sub(r'\s+[Tt]o\s+[Tt]aste\s*$', '', ing_str)
    
    # 4. Normalize common unit abbreviations
    ing_str = re.sub(r'\bTbs\b', 'Tbsp', ing_str, flags=re.IGNORECASE)
    ing_str = re.sub(r'\bc\b', 'cup', ing_str, flags=re.IGNORECASE)
    ing_str = re.sub(r'\bTbsp\b', 'tablespoon', ing_str, flags=re.IGNORECASE)
    ing_str = re.sub(r'\bTsp\b', 'teaspoon', ing_str, flags=re.IGNORECASE)
    
    ing_str = ing_str.strip()
    
    # Handle parentheses: extract weight/size info
    # Pattern 1: "2 (16 oz.) pkg. frozen corn" -> quantity=2, unit="16 oz pkg", ingredient="frozen corn"
    # Pattern 2: "1 lb. (3 1/2 c.) sugar" -> quantity=1, unit="lb", ingredient="sugar"
    # Pattern 3: "1/2 c. nuts (pecans)" -> extract pecans as part of ingredient
    paren_match = re.search(r'\(([^)]+)\)', ing_str)
    if paren_match:
        content_in_parens = paren_match.group(1)
        
        # Check if parentheses contain a weight/volume (has numbers)
        has_numbers = bool(re.search(r'\d', content_in_parens))
        
        if has_numbers:
            # Extract quantity/unit info from parentheses (e.g., "16 oz")
            ing_str_without_parens = ing_str[:paren_match.start()] + ing_str[paren_match.end():]
            parts = ing_str_without_parens.strip().split(maxsplit=2)
            
            if len(parts) >= 1:
                try:
                    quantity = _parse_quantity(parts[0])
                    
                    # If there's a unit after quantity (before parens), combine with paren content
                    if len(parts) >= 2:
                        unit_outside = parts[1]
                        # Combine: "2 pkg (16 oz)" -> "16 oz pkg"
                        unit = f"{content_in_parens} {unit_outside}".strip()
                        ingredient = parts[2] if len(parts) > 2 else ""
                    else:
                        unit = content_in_parens.strip()
                        ingredient = ""
                    
                    return ParsedIngredient(
                        ingredient=" ".join(ingredient.split()) or original_str,
                        quantity=quantity,
                        unit=unit,
                        modifier=modifier,
                    )
                except (ValueError, IndexError):
                    pass
        else:
            # Parentheses contain ingredient detail (e.g., "nuts (pecans)")
            # Remove parens but keep content as part of ingredient
            ing_str = ing_str.replace(f"({content_in_parens})", content_in_parens)
    
    # Handle mixed numbers with fractions: "3 1/2 cup", "1 1/2 lb", "2/3 cup"
    # Pattern 1: "3 1/2 cup" -> 3.5
    # Pattern 2: "2/3 cup" -> 0.667
    mixed_fraction_match = re.match(r'^(\d+)\s+(\d+/\d+)\s+(.+)', ing_str)
    if mixed_fraction_match:
        whole = int(mixed_fraction_match.group(1))
        fraction_str = mixed_fraction_match.group(2)
        rest = mixed_fraction_match.group(3)
        
        try:
            fraction_val = _parse_quantity(fraction_str)
            quantity = whole + fraction_val
            
            rest_parts = rest.split(maxsplit=1)
            unit = rest_parts[0] if rest_parts else "serving"
            ingredient = rest_parts[1] if len(rest_parts) > 1 else ""
            
            return ParsedIngredient(
                ingredient=ingredient.strip() or original_str,
                quantity=quantity,
                unit=unit,
                modifier=modifier,
            )
        except (ValueError, ZeroDivisionError):
            pass
    
    # Handle simple fractions at start: "2/3 cup", "3/4 tsp"
    simple_fraction_match = re.match(r'^(\d+/\d+)\s+(.+)', ing_str)
    if simple_fraction_match:
        fraction_str = simple_fraction_match.group(1)
        rest = simple_fraction_match.group(2)
        
        try:
            quantity = _parse_quantity(fraction_str)
            rest_parts = rest.split(maxsplit=1)
            unit = rest_parts[0] if rest_parts else "serving"
            ingredient = rest_parts[1] if len(rest_parts) > 1 else ""
            
            return ParsedIngredient(
                ingredient=ingredient.strip() or original_str,
                quantity=quantity,
                unit=unit,
                modifier=modifier,
            )
        except (ValueError, ZeroDivisionError):
            pass
    
    # Handle fraction numbers (34 = 3/4, 14 = 1/4, 18 = 1/8) - legacy format
    fraction_match = re.match(r'^(\d+)(\s+)(.+)', ing_str)
    if fraction_match:
        num_str = fraction_match.group(1)
        rest = fraction_match.group(3)
        
        if len(num_str) == 2 and num_str[1] in ['2', '4', '8']:
            try:
                numerator = int(num_str[0])
                denominator = int(num_str[1])
                quantity = numerator / denominator
                
                rest_parts = rest.split(maxsplit=1)
                unit = rest_parts[0] if rest_parts else "serving"
                ingredient = rest_parts[1] if len(rest_parts) > 1 else ""
                
                return ParsedIngredient(
                    ingredient=ingredient.strip() or original_str,
                    quantity=quantity,
                    unit=unit,
                    modifier=modifier,
                )
            except (ValueError, ZeroDivisionError):
                pass
    
    # Handle size descriptors: "1 small jar", "1 large can", "1 medium onion"
    size_match = re.match(r'^(\d+(?:/\d+)?)\s+(small|large|medium|qt|quart|pint|pt)\s+(.+)', ing_str, re.IGNORECASE)
    if size_match:
        quantity_str = size_match.group(1)
        size = size_match.group(2)
        rest = size_match.group(3)
        
        try:
            quantity = _parse_quantity(quantity_str)
            rest_parts = rest.split(maxsplit=1)
            
            # Check if next part is a container unit
            if rest_parts and rest_parts[0].lower() in ['can', 'jar', 'box', 'pkg', 'package', 'container', 'carton']:
                unit = f"{size} {rest_parts[0]}"
                ingredient = rest_parts[1] if len(rest_parts) > 1 else ""
            else:
                unit = size
                ingredient = rest
            
            return ParsedIngredient(
                ingredient=ingredient.strip() or original_str,
                quantity=quantity,
                unit=unit,
                modifier=modifier,
            )
        except (ValueError, IndexError):
            pass
    
    # Standard parsing: "quantity unit ingredient" or "quantity ingredient"
    parts = ing_str.split(maxsplit=3)
    
    if len(parts) >= 1:
        # Try to parse first part as quantity
        try:
            quantity = _parse_quantity(parts[0])
            
            if len(parts) >= 3:
                # Format: "quantity unit ingredient"
                unit = parts[1]
                ingredient = " ".join(parts[2:])
            elif len(parts) == 2:
                # Format: "quantity ingredient" or "quantity unit"
                # Check if second part looks like a unit (including container units)
                unit_list = ['cup', 'cups', 'tablespoon', 'tablespoons', 'teaspoon', 'teaspoons',
                            'oz', 'ounce', 'ounces', 'lb', 'lbs', 'pound', 'pounds',
                            'g', 'gram', 'grams', 'kg', 'kilogram', 'kilograms',
                            'ml', 'milliliter', 'milliliters', 'l', 'liter', 'liters',
                            'slice', 'slices', 'clove', 'cloves', 'piece', 'pieces',
                            'can', 'cans', 'jar', 'jars', 'box', 'boxes', 'pkg', 'package', 'packages',
                            'container', 'containers', 'carton', 'cartons', 'bottle', 'bottles',
                            'qt', 'quart', 'quarts', 'pint', 'pints', 'pt']
                
                if parts[1].lower() in unit_list:
                    unit = parts[1]
                    ingredient = ""
                else:
                    unit = "serving"
                    ingredient = parts[1]
            else:
                unit = "serving"
                ingredient = ""
            
            return ParsedIngredient(
                ingredient=ingredient.strip() or original_str,
                quantity=quantity,
                unit=unit,
                modifier=modifier,
            )
        except (ValueError, IndexError):
            pass
    
    # Fallback: treat entire string as ingredient with quantity 1
    return ParsedIngredient(
        ingredient=original_str,
        quantity=1.0,
        unit="serving",
        modifier=modifier,
    )


def _parse_quantity(qty_str: str) -> float:
    """
    Parse quantity string to float.
    
    Handles:
    - Decimals: "2.5"
    - Fractions: "1/2", "3/4"
    - Whole numbers: "2"
    
    Args:
        qty_str: Quantity string
        
    Returns:
        Float value
    """
    qty_str = qty_str.strip()
    
    # Try fraction first: "1/2", "3/4"
    if '/' in qty_str:
        parts = qty_str.split('/')
        if len(parts) == 2:
            try:
                numerator = float(parts[0])
                denominator = float(parts[1])
                if denominator != 0:
                    return numerator / denominator
            except (ValueError, ZeroDivisionError):
                pass
    
    # Try decimal
    try:
        return float(qty_str)
    except ValueError:
        return 1.0

