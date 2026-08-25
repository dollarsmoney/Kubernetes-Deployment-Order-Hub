import Home from './pages/Home.jsx';

/**
 * There is deliberately no router.
 *
 * The brief asked for a single polished homepage, and adding react-router for
 * one page would be architecture for its own sake. If a menu page or a cart
 * page were added later, this is the one file that would change.
 */
export default function App() {
  return <Home />;
}
