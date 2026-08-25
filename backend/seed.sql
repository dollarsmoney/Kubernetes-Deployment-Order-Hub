-- ============================================================================
-- seed.sql — schema + sample data for Jollof Run
-- ============================================================================
-- Applied by db.init_schema() at backend startup.
--
-- Written to be IDEMPOTENT: every statement is safe to run repeatedly, because
-- with replicas: 2 both backend pods start at roughly the same time and both
-- will run this. CREATE TABLE IF NOT EXISTS and ON CONFLICT DO NOTHING are what
-- keep that from being a problem.
--
-- Image URLs point at Unsplash (free to use under the Unsplash Licence).
-- ?auto=format&fit=crop&w=800&q=80 asks Unsplash's CDN to resize and re-encode,
-- which keeps page weight down.
-- ============================================================================

CREATE TABLE IF NOT EXISTS restaurants (
    id                 SERIAL PRIMARY KEY,
    name               TEXT           NOT NULL,
    description        TEXT           NOT NULL,
    image_url          TEXT           NOT NULL,
    rating             NUMERIC(2, 1)  NOT NULL DEFAULT 0.0,
    location           TEXT           NOT NULL,
    cuisine            TEXT           NOT NULL DEFAULT 'Nigerian',
    delivery_time_mins INTEGER        NOT NULL DEFAULT 30,
    delivery_fee       NUMERIC(10, 2) NOT NULL DEFAULT 500.00,
    created_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS foods (
    id            SERIAL PRIMARY KEY,
    -- ON DELETE CASCADE: removing a restaurant removes its menu. Without it,
    -- a delete fails on the foreign-key constraint and you leak orphan rows.
    restaurant_id INTEGER        NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name          TEXT           NOT NULL,
    description   TEXT           NOT NULL,
    price         NUMERIC(10, 2) NOT NULL,
    image_url     TEXT           NOT NULL,
    category      TEXT           NOT NULL DEFAULT 'Mains',
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Indexes on the columns we actually filter and sort by. On a few dozen rows
-- PostgreSQL will ignore them and do a sequential scan anyway — they are here
-- because knowing WHICH columns to index is the point, and because
-- log_min_duration_statement in rds.tf will show you the difference if you
-- ever seed this with 100,000 rows.
CREATE INDEX IF NOT EXISTS idx_foods_restaurant ON foods(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_foods_category   ON foods(category);
CREATE INDEX IF NOT EXISTS idx_restaurants_rating ON restaurants(rating DESC);

-- ----------------------------------------------------------------------------
-- Restaurants
-- ----------------------------------------------------------------------------
-- Explicit ids so the foods below can reference them deterministically, and so
-- re-running this file collides on the primary key rather than inserting
-- duplicates.
-- ----------------------------------------------------------------------------

INSERT INTO restaurants (id, name, description, image_url, rating, location, cuisine, delivery_time_mins, delivery_fee) VALUES
(1, 'Iya Basira Buka',
 'Forty years of firewood jollof and smoky party rice, served from a courtyard in Surulere.',
 'https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=800&q=80',
 4.8, 'Surulere, Lagos', 'Nigerian', 25, 700.00),

(2, 'Mama Nkechi Kitchen',
 'Eastern comfort food. Egusi thick enough to stand a spoon in, and the softest pounded yam in Yaba.',
 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?auto=format&fit=crop&w=800&q=80',
 4.7, 'Yaba, Lagos', 'Igbo', 35, 800.00),

(3, 'Suya Republic',
 'Charcoal grills fired from 4pm. Ram suya, kilishi and yaji ground fresh every morning.',
 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=800&q=80',
 4.9, 'Wuse II, Abuja', 'Grill', 20, 600.00),

(4, 'The Amala Spot',
 'Ewedu, gbegiri and amala done the Ibadan way. Abula that tastes like someone''s grandmother made it.',
 'https://images.unsplash.com/photo-1543353071-873f17a7a088?auto=format&fit=crop&w=800&q=80',
 4.6, 'Ikeja, Lagos', 'Yoruba', 30, 650.00),

(5, 'Calabar Kitchen',
 'Afang, edikaikong and seafood okro from the South-South. Rich, green, and generous with the periwinkle.',
 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=800&q=80',
 4.8, 'Lekki Phase 1, Lagos', 'Efik', 40, 1200.00),

(6, 'Zaria Grill House',
 'Northern classics — tuwo shinkafa, miyan kuka, and masa fried to order.',
 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=800&q=80',
 4.5, 'Garki, Abuja', 'Hausa', 35, 700.00),

(7, 'Small Chops Republic',
 'Puff-puff, samosa, spring roll and peppered gizzard. Party trays delivered anywhere on the mainland.',
 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=800&q=80',
 4.7, 'Gbagada, Lagos', 'Small Chops', 25, 500.00),

(8, 'Port Harcourt Bole Bar',
 'Roasted plantain and fish with that palm-oil-and-pepper sauce, exactly as it is done in PH.',
 'https://images.unsplash.com/photo-1598866594230-a7c12756260f?auto=format&fit=crop&w=800&q=80',
 4.6, 'GRA Phase 2, Port Harcourt', 'Rivers', 30, 750.00)
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Foods
-- ----------------------------------------------------------------------------
-- Prices in Naira.
-- ----------------------------------------------------------------------------

INSERT INTO foods (id, restaurant_id, name, description, price, image_url, category) VALUES
-- Iya Basira Buka
(1, 1, 'Party Jollof Rice', 'Smoky firewood jollof with fried plantain and coleslaw.', 3500.00, 'https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=600&q=80', 'Rice'),
(2, 1, 'Ofada Rice & Ayamase', 'Unpolished ofada with green pepper sauce, assorted meat and boiled egg.', 4800.00, 'https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=600&q=80', 'Rice'),
(3, 1, 'Fried Rice & Chicken', 'Vegetable fried rice with a quarter grilled chicken.', 4200.00, 'https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=600&q=80', 'Rice'),
(4, 1, 'Moi Moi', 'Steamed bean pudding with fish and egg, wrapped in leaves.', 1200.00, 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?auto=format&fit=crop&w=600&q=80', 'Sides'),

-- Mama Nkechi Kitchen
(5, 2, 'Egusi & Pounded Yam', 'Melon seed soup with goat meat, stockfish and bitter leaf.', 5500.00, 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?auto=format&fit=crop&w=600&q=80', 'Swallow'),
(6, 2, 'Oha Soup & Fufu', 'Oha leaves in a cocoyam-thickened broth with assorted meat.', 5200.00, 'https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=600&q=80', 'Swallow'),
(7, 2, 'Nsala (White Soup)', 'Peppery catfish soup, no palm oil, thickened with yam.', 6000.00, 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=600&q=80', 'Soup'),
(8, 2, 'Abacha', 'African salad — shredded cassava with ugba, garden egg and fish.', 3000.00, 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=600&q=80', 'Sides'),

-- Suya Republic
(9, 3, 'Ram Suya (Full Wrap)', 'Charcoal-grilled ram in yaji spice, with onions, tomato and extra pepper.', 4500.00, 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=600&q=80', 'Grill'),
(10, 3, 'Chicken Suya Skewers', 'Six skewers of spiced chicken, grilled to order.', 3800.00, 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=600&q=80', 'Grill'),
(11, 3, 'Kilishi (250g)', 'Sun-dried spiced beef. Sweet, hot, and dangerously moreish.', 5000.00, 'https://images.unsplash.com/photo-1602881917445-0b1ba0e0a2ea?auto=format&fit=crop&w=600&q=80', 'Grill'),
(12, 3, 'Asun', 'Smoked goat meat tossed in scotch bonnet and onions.', 5500.00, 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=600&q=80', 'Grill'),

-- The Amala Spot
(13, 4, 'Abula (Amala Complete)', 'Amala with ewedu, gbegiri and buka stew. Choose your protein.', 4000.00, 'https://images.unsplash.com/photo-1543353071-873f17a7a088?auto=format&fit=crop&w=600&q=80', 'Swallow'),
(14, 4, 'Amala & Efo Riro', 'Soft amala with rich spinach stew, ponmo and beef.', 4200.00, 'https://images.unsplash.com/photo-1518492104633-130d0cc84637?auto=format&fit=crop&w=600&q=80', 'Swallow'),
(15, 4, 'Ewa Agoyin & Agege Bread', 'Mashed beans with that black pepper sauce, and soft Agege bread.', 2500.00, 'https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=600&q=80', 'Mains'),

-- Calabar Kitchen
(16, 5, 'Afang Soup', 'Afang and waterleaf with periwinkle, dry fish and beef.', 6500.00, 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=600&q=80', 'Soup'),
(17, 5, 'Edikaikong', 'Ugu and waterleaf, heavy on the assorted meat.', 6800.00, 'https://images.unsplash.com/photo-1512852939750-1305098529bf?auto=format&fit=crop&w=600&q=80', 'Soup'),
(18, 5, 'Seafood Okro', 'Okro with prawns, crab and periwinkle.', 7200.00, 'https://images.unsplash.com/photo-1559737558-2f5a35f4523b?auto=format&fit=crop&w=600&q=80', 'Soup'),
(19, 5, 'Catfish Pepper Soup', 'Fresh catfish in a clear, fiery broth with uziza.', 5000.00, 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=600&q=80', 'Soup'),

-- Zaria Grill House
(20, 6, 'Tuwo Shinkafa & Miyan Kuka', 'Rice pudding with baobab leaf soup and beef.', 3800.00, 'https://images.unsplash.com/photo-1585032226651-759b368d7246?auto=format&fit=crop&w=600&q=80', 'Swallow'),
(21, 6, 'Masa & Miyan Taushe', 'Fermented rice cakes with pumpkin and groundnut stew.', 3200.00, 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=600&q=80', 'Mains'),
(22, 6, 'Dan Wake', 'Bean dumplings tossed in oil, pepper and onions.', 2200.00, 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?auto=format&fit=crop&w=600&q=80', 'Sides'),

-- Small Chops Republic
(23, 7, 'Small Chops Platter', 'Puff-puff, samosa, spring roll and peppered gizzard. Serves 2-3.', 6000.00, 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=600&q=80', 'Small Chops'),
(24, 7, 'Puff-Puff (12 pieces)', 'Golden, airy, faintly sweet. Best eaten hot.', 1500.00, 'https://images.unsplash.com/photo-1509365465985-25d11c17e812?auto=format&fit=crop&w=600&q=80', 'Small Chops'),
(25, 7, 'Peppered Gizzard', 'Gizzard in a thick, smoky pepper sauce.', 3500.00, 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=600&q=80', 'Small Chops'),
(26, 7, 'Chin Chin (500g)', 'Crunchy fried dough cubes, lightly sweetened.', 2000.00, 'https://images.unsplash.com/photo-1558961363-fa8fdf82db35?auto=format&fit=crop&w=600&q=80', 'Snacks'),

-- Port Harcourt Bole Bar
(27, 8, 'Bole & Fish', 'Roasted plantain with roasted fish and palm oil pepper sauce.', 4500.00, 'https://images.unsplash.com/photo-1598866594230-a7c12756260f?auto=format&fit=crop&w=600&q=80', 'Grill'),
(28, 8, 'Bole & Groundnut', 'Roasted plantain with roasted groundnut. The classic PH street pairing.', 1800.00, 'https://images.unsplash.com/photo-1528825871115-3581a5387919?auto=format&fit=crop&w=600&q=80', 'Grill'),
(29, 8, 'Native Jollof (Iwuk Edesi)', 'Palm-oil jollof with dry fish and periwinkle.', 4800.00, 'https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=600&q=80', 'Rice'),
(30, 8, 'Chapman', 'The Nigerian classic — bitters, grenadine, citrus and cucumber.', 1500.00, 'https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=600&q=80', 'Drinks')
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Reset the SERIAL sequences.
--
-- Inserting explicit ids does NOT advance the sequence, so the next INSERT
-- without an id would try id=1 and fail with a duplicate key error. This is a
-- classic PostgreSQL foot-gun after any seed or data import.
-- ----------------------------------------------------------------------------

SELECT setval('restaurants_id_seq', COALESCE((SELECT MAX(id) FROM restaurants), 1), true);
SELECT setval('foods_id_seq',       COALESCE((SELECT MAX(id) FROM foods), 1), true);
