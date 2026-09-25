using System.Reflection;

namespace KleeneStar
{
    /// <summary>
    /// Serves as the entry point for the kleenestar application.
    /// </summary>
    internal class Program
    {
        /// <summary>
        /// The entry point of the KleeneStar application.
        /// </summary>
        /// <param name="args">Command-line arguments passed to the application.</param>
        /// <returns>The exit code of the application.</returns>
        private static int Main(string[] args)
        {
            var app = new WebExpress.WebCore.WebEx()
            {
                Name = Assembly.GetExecutingAssembly().GetName().Name
            };

            return app.Execution(args);
        }
    }
}
