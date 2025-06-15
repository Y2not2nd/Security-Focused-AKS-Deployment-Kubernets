import { Component } from '@angular/core';
import { ApiService } from './api.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html'
})
export class AppComponent {
  title = 'Secure AKS Demo';
  backendMessage: string = '';

  constructor(private api: ApiService) {}

  pingBackend(): void {
    this.api.ping().subscribe(
      data => {
        this.backendMessage = data.message;
      },
      error => {
        console.error('API error:', error);
        this.backendMessage = 'Error: ' + error.statusText;
      }
    );
  }
} 