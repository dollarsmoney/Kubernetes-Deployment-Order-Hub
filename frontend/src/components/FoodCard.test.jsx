import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import FoodCard from './FoodCard.jsx';

const FOOD = {
  id: 1,
  restaurant_id: 1,
  name: 'Party Jollof Rice',
  description: 'Smoky firewood jollof with fried plantain and coleslaw.',
  price: 3500,
  image_url: 'https://images.unsplash.com/photo-x?w=600',
  category: 'Rice',
  restaurant_name: 'Iya Basira Buka',
  restaurant_rating: 4.8,
};

describe('FoodCard', () => {
  it('renders the dish, its price and its restaurant', () => {
    render(<FoodCard food={FOOD} />);

    expect(screen.getByText('Party Jollof Rice')).toBeInTheDocument();
    expect(screen.getByText('Iya Basira Buka')).toBeInTheDocument();
    expect(screen.getByText(/3,500/)).toBeInTheDocument();
    expect(screen.getByText('Rice')).toBeInTheDocument();
  });

  it('gives the image an accessible name', () => {
    render(<FoodCard food={FOOD} />);

    // alt={name}, so the image is announced rather than skipped.
    expect(screen.getByRole('img', { name: 'Party Jollof Rice' })).toBeInTheDocument();
  });

  it('labels the add button with the dish name', () => {
    render(<FoodCard food={FOOD} />);

    // Three identical "+" buttons in a grid are indistinguishable to a screen
    // reader without this.
    expect(
      screen.getByRole('button', { name: 'Add Party Jollof Rice to cart' }),
    ).toBeInTheDocument();
  });

  it('calls onAdd with the food object', () => {
    const onAdd = vi.fn();
    render(<FoodCard food={FOOD} onAdd={onAdd} />);

    fireEvent.click(screen.getByRole('button', { name: /add/i }));

    expect(onAdd).toHaveBeenCalledTimes(1);
    expect(onAdd).toHaveBeenCalledWith(FOOD);
  });

  it('does not throw when onAdd is omitted', () => {
    // The optional-call guard (`onAdd?.(food)`) — a card rendered without a
    // handler should be inert, not a crash.
    render(<FoodCard food={FOOD} />);

    expect(() =>
      fireEvent.click(screen.getByRole('button', { name: /add/i })),
    ).not.toThrow();
  });

  it('tolerates a missing restaurant rating', () => {
    const { restaurant_rating: _omitted, ...withoutRating } = FOOD;

    render(<FoodCard food={withoutRating} />);

    expect(screen.getByText('Party Jollof Rice')).toBeInTheDocument();
  });
});
