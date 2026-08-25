/**
 * fallback.js — the same shape the API returns, hardcoded.
 *
 * WHY THIS EXISTS, and why it is not cheating:
 *
 * The frontend is built and demonstrated in Phase 3, before RDS exists
 * (Phase 7). Without a fallback, the homepage would be an empty grid until
 * halfway through the project, and every screenshot would be of a broken page.
 *
 * More practically: a food-delivery homepage that renders a blank white void
 * when its API is slow is a bad homepage. Real products ship a static
 * first-paint and hydrate over it.
 *
 * The contract: this data MIRRORS backend/seed.sql exactly. When the API
 * responds, its data replaces this — see useCatalog() in hooks.js. A banner
 * appears in the corner so you always know which source you are looking at,
 * and Phase 12's "frontend talks to backend" test is checking precisely that
 * the banner is absent.
 */

export const FALLBACK_RESTAURANTS = [
  {
    id: 1,
    name: 'Iya Basira Buka',
    description:
      'Forty years of firewood jollof and smoky party rice, served from a courtyard in Surulere.',
    image_url:
      'https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=800&q=80',
    rating: 4.8,
    location: 'Surulere, Lagos',
    cuisine: 'Nigerian',
    delivery_time_mins: 25,
    delivery_fee: 700,
  },
  {
    id: 2,
    name: 'Mama Nkechi Kitchen',
    description:
      'Eastern comfort food. Egusi thick enough to stand a spoon in, and the softest pounded yam in Yaba.',
    image_url:
      'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?auto=format&fit=crop&w=800&q=80',
    rating: 4.7,
    location: 'Yaba, Lagos',
    cuisine: 'Igbo',
    delivery_time_mins: 35,
    delivery_fee: 800,
  },
  {
    id: 3,
    name: 'Suya Republic',
    description:
      'Charcoal grills fired from 4pm. Ram suya, kilishi and yaji ground fresh every morning.',
    image_url:
      'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=800&q=80',
    rating: 4.9,
    location: 'Wuse II, Abuja',
    cuisine: 'Grill',
    delivery_time_mins: 20,
    delivery_fee: 600,
  },
  {
    id: 4,
    name: 'The Amala Spot',
    description:
      'Ewedu, gbegiri and amala done the Ibadan way. Abula that tastes like someone’s grandmother made it.',
    image_url:
      'https://images.unsplash.com/photo-1543353071-873f17a7a088?auto=format&fit=crop&w=800&q=80',
    rating: 4.6,
    location: 'Ikeja, Lagos',
    cuisine: 'Yoruba',
    delivery_time_mins: 30,
    delivery_fee: 650,
  },
  {
    id: 5,
    name: 'Calabar Kitchen',
    description:
      'Afang, edikaikong and seafood okro from the South-South. Rich, green, and generous with the periwinkle.',
    image_url:
      'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=800&q=80',
    rating: 4.8,
    location: 'Lekki Phase 1, Lagos',
    cuisine: 'Efik',
    delivery_time_mins: 40,
    delivery_fee: 1200,
  },
  {
    id: 6,
    name: 'Zaria Grill House',
    description:
      'Northern classics — tuwo shinkafa, miyan kuka, and masa fried to order.',
    image_url:
      'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=800&q=80',
    rating: 4.5,
    location: 'Garki, Abuja',
    cuisine: 'Hausa',
    delivery_time_mins: 35,
    delivery_fee: 700,
  },
  {
    id: 7,
    name: 'Small Chops Republic',
    description:
      'Puff-puff, samosa, spring roll and peppered gizzard. Party trays delivered anywhere on the mainland.',
    image_url:
      'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=800&q=80',
    rating: 4.7,
    location: 'Gbagada, Lagos',
    cuisine: 'Small Chops',
    delivery_time_mins: 25,
    delivery_fee: 500,
  },
  {
    id: 8,
    name: 'Port Harcourt Bole Bar',
    description:
      'Roasted plantain and fish with that palm-oil-and-pepper sauce, exactly as it is done in PH.',
    image_url:
      'https://images.unsplash.com/photo-1598866594230-a7c12756260f?auto=format&fit=crop&w=800&q=80',
    rating: 4.6,
    location: 'GRA Phase 2, Port Harcourt',
    cuisine: 'Rivers',
    delivery_time_mins: 30,
    delivery_fee: 750,
  },
];

export const FALLBACK_FOODS = [
  { id: 1, restaurant_id: 1, name: 'Party Jollof Rice', description: 'Smoky firewood jollof with fried plantain and coleslaw.', price: 3500, category: 'Rice', restaurant_name: 'Iya Basira Buka', restaurant_rating: 4.8, image_url: 'https://images.unsplash.com/photo-1604329760661-e71dc83f8f26?auto=format&fit=crop&w=600&q=80' },
  { id: 2, restaurant_id: 1, name: 'Ofada Rice & Ayamase', description: 'Unpolished ofada with green pepper sauce, assorted meat and boiled egg.', price: 4800, category: 'Rice', restaurant_name: 'Iya Basira Buka', restaurant_rating: 4.8, image_url: 'https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=600&q=80' },
  { id: 5, restaurant_id: 2, name: 'Egusi & Pounded Yam', description: 'Melon seed soup with goat meat, stockfish and bitter leaf.', price: 5500, category: 'Swallow', restaurant_name: 'Mama Nkechi Kitchen', restaurant_rating: 4.7, image_url: 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?auto=format&fit=crop&w=600&q=80' },
  { id: 6, restaurant_id: 2, name: 'Oha Soup & Fufu', description: 'Oha leaves in a cocoyam-thickened broth with assorted meat.', price: 5200, category: 'Swallow', restaurant_name: 'Mama Nkechi Kitchen', restaurant_rating: 4.7, image_url: 'https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=600&q=80' },
  { id: 9, restaurant_id: 3, name: 'Ram Suya (Full Wrap)', description: 'Charcoal-grilled ram in yaji spice, with onions, tomato and extra pepper.', price: 4500, category: 'Grill', restaurant_name: 'Suya Republic', restaurant_rating: 4.9, image_url: 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?auto=format&fit=crop&w=600&q=80' },
  { id: 12, restaurant_id: 3, name: 'Asun', description: 'Smoked goat meat tossed in scotch bonnet and onions.', price: 5500, category: 'Grill', restaurant_name: 'Suya Republic', restaurant_rating: 4.9, image_url: 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=600&q=80' },
  { id: 13, restaurant_id: 4, name: 'Abula (Amala Complete)', description: 'Amala with ewedu, gbegiri and buka stew. Choose your protein.', price: 4000, category: 'Swallow', restaurant_name: 'The Amala Spot', restaurant_rating: 4.6, image_url: 'https://images.unsplash.com/photo-1543353071-873f17a7a088?auto=format&fit=crop&w=600&q=80' },
  { id: 15, restaurant_id: 4, name: 'Ewa Agoyin & Agege Bread', description: 'Mashed beans with that black pepper sauce, and soft Agege bread.', price: 2500, category: 'Mains', restaurant_name: 'The Amala Spot', restaurant_rating: 4.6, image_url: 'https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=600&q=80' },
  { id: 16, restaurant_id: 5, name: 'Afang Soup', description: 'Afang and waterleaf with periwinkle, dry fish and beef.', price: 6500, category: 'Soup', restaurant_name: 'Calabar Kitchen', restaurant_rating: 4.8, image_url: 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=600&q=80' },
  { id: 19, restaurant_id: 5, name: 'Catfish Pepper Soup', description: 'Fresh catfish in a clear, fiery broth with uziza.', price: 5000, category: 'Soup', restaurant_name: 'Calabar Kitchen', restaurant_rating: 4.8, image_url: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=600&q=80' },
  { id: 20, restaurant_id: 6, name: 'Tuwo Shinkafa & Miyan Kuka', description: 'Rice pudding with baobab leaf soup and beef.', price: 3800, category: 'Swallow', restaurant_name: 'Zaria Grill House', restaurant_rating: 4.5, image_url: 'https://images.unsplash.com/photo-1585032226651-759b368d7246?auto=format&fit=crop&w=600&q=80' },
  { id: 23, restaurant_id: 7, name: 'Small Chops Platter', description: 'Puff-puff, samosa, spring roll and peppered gizzard. Serves 2-3.', price: 6000, category: 'Small Chops', restaurant_name: 'Small Chops Republic', restaurant_rating: 4.7, image_url: 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=600&q=80' },
  { id: 24, restaurant_id: 7, name: 'Puff-Puff (12 pieces)', description: 'Golden, airy, faintly sweet. Best eaten hot.', price: 1500, category: 'Small Chops', restaurant_name: 'Small Chops Republic', restaurant_rating: 4.7, image_url: 'https://images.unsplash.com/photo-1509365465985-25d11c17e812?auto=format&fit=crop&w=600&q=80' },
  { id: 27, restaurant_id: 8, name: 'Bole & Fish', description: 'Roasted plantain with roasted fish and palm oil pepper sauce.', price: 4500, category: 'Grill', restaurant_name: 'Port Harcourt Bole Bar', restaurant_rating: 4.6, image_url: 'https://images.unsplash.com/photo-1598866594230-a7c12756260f?auto=format&fit=crop&w=600&q=80' },
  { id: 29, restaurant_id: 8, name: 'Native Jollof (Iwuk Edesi)', description: 'Palm-oil jollof with dry fish and periwinkle.', price: 4800, category: 'Rice', restaurant_name: 'Port Harcourt Bole Bar', restaurant_rating: 4.6, image_url: 'https://images.unsplash.com/photo-1596797038530-2c107229654b?auto=format&fit=crop&w=600&q=80' },
  { id: 30, restaurant_id: 8, name: 'Chapman', description: 'The Nigerian classic — bitters, grenadine, citrus and cucumber.', price: 1500, category: 'Drinks', restaurant_name: 'Port Harcourt Bole Bar', restaurant_rating: 4.6, image_url: 'https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=600&q=80' },
];

/**
 * Category rail. `key` matches the `category` column in the foods table, so
 * clicking a category filters the real API data too.
 *
 * These are emoji rather than icon components on purpose: they render at any
 * size, need no import, add zero bytes to the bundle, and read as friendly —
 * which suits a food brand.
 */
export const CATEGORIES = [
  { key: 'Rice',        label: 'Jollof & Rice', emoji: '🍚', tint: 'from-brand-100 to-brand-50' },
  { key: 'Swallow',     label: 'Swallow',       emoji: '🍲', tint: 'from-jollof-100 to-jollof-50' },
  { key: 'Soup',        label: 'Soups',         emoji: '🥣', tint: 'from-emerald-100 to-emerald-50' },
  { key: 'Grill',       label: 'Suya & Grill',  emoji: '🍢', tint: 'from-orange-100 to-orange-50' },
  { key: 'Small Chops', label: 'Small Chops',   emoji: '🥟', tint: 'from-purple-100 to-purple-50' },
  { key: 'Mains',       label: 'Mains',         emoji: '🍛', tint: 'from-sky-100 to-sky-50' },
  { key: 'Sides',       label: 'Sides',         emoji: '🫓', tint: 'from-lime-100 to-lime-50' },
  { key: 'Drinks',      label: 'Drinks',        emoji: '🥤', tint: 'from-pink-100 to-pink-50' },
];

/** Delivery areas for the location picker in the hero and navbar. */
export const DELIVERY_AREAS = [
  { city: 'Lagos',          areas: ['Lekki Phase 1', 'Victoria Island', 'Ikeja GRA', 'Surulere', 'Yaba', 'Gbagada', 'Ajah', 'Ikoyi'] },
  { city: 'Abuja',          areas: ['Wuse II', 'Garki', 'Maitama', 'Gwarinpa', 'Jabi'] },
  { city: 'Port Harcourt',  areas: ['GRA Phase 2', 'Trans Amadi', 'Rumuokoro'] },
];
