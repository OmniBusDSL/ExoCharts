import { Injectable } from '@angular/core';
import { BehaviorSubject, Observable } from 'rxjs';

// Would import from actual location
// import { ExoGrid } from '../../js/index.js';

@Injectable({
  providedIn: 'root'
})
export class ExoGridService {
  private exoGrid: any;
  private connectedSubject = new BehaviorSubject<boolean>(false);
  private tickCountSubject = new BehaviorSubject<number>(0);
  private matrixSubject = new BehaviorSubject<any>(null);

  public connected$ = this.connectedSubject.asObservable();
  public tickCount$ = this.tickCountSubject.asObservable();
  public matrix$ = this.matrixSubject.asObservable();

  constructor() {
    // Dynamically load ExoGrid for browser compatibility
    this.initializeExoGrid();
  }

  private initializeExoGrid(): void {
    // const { ExoGrid } = require('../../js/index.js');
    // this.exoGrid = new ExoGrid();
  }

  connect(host: string = 'localhost', port: number = 9090): void {
    if (!this.exoGrid) return;

    this.exoGrid.on('connected', () => {
      this.connectedSubject.next(true);
    });

    this.exoGrid.on('disconnected', () => {
      this.connectedSubject.next(false);
    });

    this.exoGrid.on('tick', () => {
      this.tickCountSubject.next(this.tickCountSubject.value + 1);
    });

    this.exoGrid.on('matrix', (data: any) => {
      this.matrixSubject.next(data);
    });

    this.exoGrid.connect();
  }

  disconnect(): void {
    if (this.exoGrid) {
      this.exoGrid.disconnect();
    }
  }

  async getMatrix(ticker: string = 'BTC', timeframe: string = '1s'): Promise<any> {
    if (!this.exoGrid) return null;
    return await this.exoGrid.getMatrix(ticker, timeframe);
  }

  async getTicks(): Promise<any> {
    if (!this.exoGrid) return null;
    return await this.exoGrid.getTickCounts();
  }
}
