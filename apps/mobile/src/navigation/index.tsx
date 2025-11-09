import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createStackNavigator } from '@react-navigation/stack';
import type { RootStackParamList } from './types';

// Import screens
import HomeScreen from '../screens/HomeScreen';

// Create navigator
const Stack = createStackNavigator<RootStackParamList>();

// Root Stack Navigator - handles all screens
export default function Navigation() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name="Home" component={HomeScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

