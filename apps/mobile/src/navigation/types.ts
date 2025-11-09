// Define the param list for each navigator
export type RootStackParamList = {
  Home: undefined;
  Camera: undefined;
  Settings: undefined;
};

// Drawer types will be added later when drawer navigator is implemented
export type DrawerParamList = {
  Home: undefined;
  Settings: undefined;
};

// Export a type that combines all navigation props
export type NavigationProps<T extends keyof RootStackParamList> = {
  navigation: {
    navigate: (screen: T, params?: RootStackParamList[T]) => void;
    goBack: () => void;
  };
  route: {
    params: RootStackParamList[T];
  };
};

