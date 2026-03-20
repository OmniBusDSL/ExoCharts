from setuptools import setup, find_packages

setup(
    name='exogrid',
    version='1.0.0',
    description='Real-time cryptocurrency market data streaming SDK',
    author='ExoGridChart',
    author_email='',
    url='https://github.com/SAVACAZAN/ExoGridChart',
    packages=find_packages(),
    python_requires='>=3.8',
    install_requires=[
        'requests>=2.28.0',
    ],
    extras_require={
        'dev': ['pytest>=7.0', 'black', 'mypy'],
    },
    classifiers=[
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'License :: OSI Approved :: MIT License',
        'Topic :: Office/Business :: Financial :: Investment',
    ],
)
