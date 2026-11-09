import './style.css';
import { App } from './ui/app';

declare global {
  interface Window {
    app: App;
  }
}

window.app = new App();
