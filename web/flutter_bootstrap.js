{{flutter_js}}
{{flutter_build_config}}

(() => {
  const showError = (error) => {
    if (window.zumacShowBootstrapError) {
      window.zumacShowBootstrapError(error);
      return;
    }
    console.error('Error al iniciar Zumac:', error);
  };

  _flutter.loader.load({
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
        window.__zumacFlutterStarted = true;
        if (window.zumacBootstrapReady) window.zumacBootstrapReady();
      } catch (error) {
        showError(error);
      }
    },
  }).catch(showError);
})();
