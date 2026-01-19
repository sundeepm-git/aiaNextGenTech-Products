'use client';

import { useEffect, useRef } from 'react';
import { useApp } from '@/context/AppContext';
import { Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, ArcElement, BarElement } from 'chart.js';
import { Line, Doughnut, Bar } from 'react-chartjs-2';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend
);

// Global defaults for better visibility on dark themes
ChartJS.defaults.color = '#e2e8f0'; 
ChartJS.defaults.borderColor = 'rgba(255, 255, 255, 0.1)';

// Theme color mapping
const getThemeColor = (theme) => {
  const colors = {
    'amazon': '251, 191, 36', // amber-400
    'meta': '56, 189, 248', // sky-400
    'corporate': '14, 165, 233', // sky-500
    'slate-pro': '56, 189, 248', // sky-400
    'teal-tech': '45, 212, 191', // teal-400
    'purple-enterprise': '192, 132, 252', // purple-400
    'olive-moss': '74, 222, 128', // green-400
    'navy-pro': '250, 204, 21', // yellow-400
    'charcoal': '248, 113, 113', // red-400
    'warm-beige': '248, 113, 113', // red-400
    'dark': '96, 165, 250', // blue-400
    'light': '59, 130, 246', // blue-500
  };
  return colors[theme] || '59, 130, 246'; // default blue
};

export const LineChart = ({ title, data, labels }) => {
  const { theme } = useApp();
  const themeColor = getThemeColor(theme);
  
  const chartData = {
    labels: labels || ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    datasets: [
      {
        label: title,
        data: data || [12, 19, 3, 5, 2, 3, 7],
        borderColor: `rgb(${themeColor})`,
        backgroundColor: `rgba(${themeColor}, 0.2)`,
        tension: 0.4,
        fill: true,
      },
    ],
  };

  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      title: {
        display: false,
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        grid: {
          color: 'rgba(255, 255, 255, 0.1)',
        },
        ticks: {
          color: '#e2e8f0',
        },
      },
      x: {
        grid: {
          color: 'rgba(255, 255, 255, 0.1)',
        },
        ticks: {
          color: '#e2e8f0',
        },
      },
    },
  };

  return (
    <div className="h-64">
      <Line data={chartData} options={options} />
    </div>
  );
};

export const DoughnutChart = ({ title, data, labels }) => {
  const chartData = {
    labels: labels || ['Active', 'Idle', 'Warning'],
    datasets: [
      {
        data: data || [300, 50, 100],
        backgroundColor: [
          'rgb(74, 222, 128)',
          'rgb(96, 165, 250)',
          'rgb(250, 204, 21)',
        ],
        borderColor: [
          'rgba(255, 255, 255, 0.1)',
          'rgba(255, 255, 255, 0.1)',
          'rgba(255, 255, 255, 0.1)',
        ],
        borderWidth: 1,
      },
    ],
  };

  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'bottom',
        labels: {
          color: '#e2e8f0',
        },
      },
    },
  };

  return (
    <div className="h-64">
      <Doughnut data={chartData} options={options} />
    </div>
  );
};

export const BarChart = ({ title, data, labels }) => {
  const { theme } = useApp();
  const themeColor = getThemeColor(theme);

  const chartData = {
    labels: labels || ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
    datasets: [
      {
        label: title,
        data: data || [65, 59, 80, 81, 56, 55],
        backgroundColor: `rgba(${themeColor}, 0.8)`,
        borderColor: `rgb(${themeColor})`,
        borderWidth: 1,
      },
    ],
  };

  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      title: {
        display: false,
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        grid: {
          color: 'rgba(255, 255, 255, 0.1)',
        },
        ticks: {
          color: '#e2e8f0',
        },
      },
      x: {
        grid: {
          display: false,
        },
        ticks: {
          color: '#e2e8f0',
        },
      },
    },
  };

  return (
    <div className="h-64">
      <Bar data={chartData} options={options} />
    </div>
  );
};
