'use client';

const CategoryCard = ({ title, description, icon: Icon, stats, children }) => {
  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
      <div className="flex items-center gap-4 mb-6">
        {Icon && (
          <div className="p-3 bg-primary-light/10 rounded-lg">
            <Icon className="h-8 w-8 text-primary" aria-hidden="true" />
          </div>
        )}
        <div className="flex-1">
          <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-1">
            {title}
          </h2>
          {description && (
            <p className="text-sm text-gray-600 dark:text-gray-400">
              {description}
            </p>
          )}
        </div>
      </div>

      {/* Stats */}
      {stats && stats.length > 0 && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          {stats.map((stat, index) => (
            <div
              key={index}
              className="p-4 bg-gray-50 dark:bg-gray-700/50 rounded-lg"
            >
              <p className="text-sm text-gray-600 dark:text-gray-400 mb-1">
                {stat.label}
              </p>
              <p className="text-2xl font-bold text-gray-900 dark:text-white">
                {stat.value}
              </p>
            </div>
          ))}
        </div>
      )}

      {/* Content */}
      {children}
    </div>
  );
};

export default CategoryCard;
